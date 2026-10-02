const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {deleteProfilePhoto} = require("../lib/moderation/deleteProfilePhoto.js");
const {reconcilePhotoModeration} = require("../lib/moderation/photoModerationService.js");

const fs = require("node:fs");
const path = require("node:path");
const PORTRAIT = fs.readFileSync(path.join(__dirname, "..", "..", "assets", "images", "portraits", "mock-01.jpg"));

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32, 1)]);

/** A member with one photo stuck in manual review (still in pending/). */
async function world({published = false} = {}) {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("mod-2", "moderator");
  await w.addStaff("support-1", "support_agent");
  const storagePath = published ? "users/member-1/profile/photos/img1.png" : "users/member-1/profile/pending/img1.png";
  await w.addMember("member-1", {
    profile: {
      profileModerationStatus: "manual_review",
      photos: [{id: "img1", storagePath, order: 0, isPrimary: true, moderationStatus: "manual_review"}],
    },
  });
  w.bucket.put(storagePath, PNG, "image/png");
  await w.db.doc("users/member-1/photoModeration/img1").set({
    imageId: "img1",
    status: "manual_review",
    reason: published ? "report:harassment" : "dimensions-unverified",
    moderatedBy: published ? "report-pipeline" : "system",
    updatedAt: new Date(w.now - 60 * 60 * 1000),
    ...(published ? {storagePath, downloadUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/p?alt=media&token=t"} : {}),
  });
  return w;
}

describe("admin photo review — the ledger stays the authority", () => {
  it("lists manual-review photos from the ledger with the user and lock state", async () => {
    const w = await world();
    const queue = await w.run(specs.adminListPhotoReviewsSpec, "mod-1", {filter: "manual_review"});
    assert.equal(queue.items.length, 1);
    assert.equal(queue.items[0].uid, "member-1");
    assert.equal(queue.items[0].imageId, "img1");
    assert.equal(queue.items[0].published, false);
    assert.equal(queue.items[0].lock, null);
  });

  it("previews the bytes server-side without any public URL", async () => {
    const w = await world();
    const preview = await w.run(specs.adminGetPhotoPreviewSpec, "mod-1", {uid: "member-1", imageId: "img1"});
    assert.equal(preview.source, "pending");
    assert.equal(preview.contentType, "image/png");
    assert.equal(Buffer.from(preview.dataBase64, "base64").equals(PNG), true);
  });

  it("approve publishes through the pipeline, writes the ledger, and settles profile visibility", async () => {
    const w = await world();
    const result = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()});
    assert.equal(result.status, "approved");
    const ledger = w.db.read("users/member-1/photoModeration/img1");
    assert.equal(ledger.status, "approved");
    assert.equal(ledger.moderatedBy, "admin_review");
    assert.equal(ledger.storagePath, "users/member-1/profile/photos/img1.png");
    assert.equal(ledger.reviewLock, undefined);
    assert.ok(w.bucket.files.has("users/member-1/profile/photos/img1.png"), "published to the server-only prefix");
    const profile = w.db.read("profiles/member-1");
    assert.equal(profile.photos[0].moderationStatus, "approved");
    assert.equal(profile.profileModerationStatus, "approved");
    const action = w.db.read(`moderationActions/${result.actionId}`);
    assert.equal(action.type, "PHOTO_APPROVED");
    assert.ok(w.db.paths().some((p) => p.startsWith("adminAuditLog/") && w.db.read(p).action === "PHOTO_APPROVED"));
  });

  it("approving a decodable photo publishes its display variants through the ledger", async () => {
    const w = await world();
    w.bucket.put("users/member-1/profile/pending/img1.png", PORTRAIT, "image/jpeg");
    await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()});
    const ledger = w.db.read("users/member-1/photoModeration/img1");
    assert.match(ledger.thumbUrl, /img1_thumb\.jpg\?alt=media&token=/);
    assert.match(ledger.cardUrl, /img1_card\.jpg\?alt=media&token=/);
    assert.ok(w.bucket.files.has("users/member-1/profile/thumbs/img1_thumb.jpg"));
    assert.ok(w.bucket.files.has("users/member-1/profile/thumbs/img1_card.jpg"));
    const photo = w.db.read("profiles/member-1").photos[0];
    assert.equal(photo.thumbUrl, ledger.thumbUrl);
    assert.equal(photo.cardUrl, ledger.cardUrl);
  });

  it("an undecodable photo is still approved, just without variants", async () => {
    const w = await world();
    const result = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()});
    assert.equal(result.status, "approved");
    const ledger = w.db.read("users/member-1/photoModeration/img1");
    assert.equal(ledger.thumbUrl ?? null, null);
    assert.equal(ledger.cardUrl ?? null, null);
  });

  it("the ledger never names the moderator (the member can read it)", async () => {
    const w = await world();
    await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()});
    const ledger = JSON.stringify(w.db.read("users/member-1/photoModeration/img1"));
    const profile = JSON.stringify(w.db.read("profiles/member-1"));
    assert.equal(ledger.includes("mod-1"), false);
    assert.equal(profile.includes("mod-1"), false);
  });

  it("reject requires a reason, quarantines the image and records the action", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "reject", idempotencyKey: key()}), "invalid_argument");
    const result = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "reject", reasonCode: "NOT_A_PERSON", idempotencyKey: key()});
    assert.equal(result.status, "rejected");
    assert.equal(w.db.read("users/member-1/photoModeration/img1").status, "rejected");
    assert.equal(w.bucket.files.has("users/member-1/profile/pending/img1.png"), false);
    assert.ok(w.bucket.files.has("moderation/quarantine/member-1/img1.png"));
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).type, "PHOTO_REJECTED");
  });

  it("rejecting an already-published (reported) photo removes it", async () => {
    const w = await world({published: true});
    const result = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "reject", reasonCode: "NUDITY_SEXUAL_CONTENT", idempotencyKey: key()});
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).type, "PHOTO_REMOVED");
    assert.equal(w.bucket.files.has("users/member-1/profile/photos/img1.png"), false);
    assert.equal(w.db.read("profiles/member-1").photos[0].downloadUrl, null);
  });

  // A report sends every photo of the member back to manual review while it
  // stays published. Approving one publishes nothing new, so the decision
  // carries no variant URLs. Those used to reach profiles.photos as undefined,
  // which Firestore refuses: the ledger said approved, the profile stayed in
  // manual_review, no action or audit record was written and a retry answered
  // photo_already_reviewed.
  it("approving an already-published (reported) photo keeps its variants and completes the decision", async () => {
    const w = await world({published: true});
    const storagePath = "users/member-1/profile/photos/img1.png";
    const downloadUrl = "https://firebasestorage.googleapis.com/v0/b/x/o/p?alt=media&token=t";
    await w.db.doc("users/member-1/photoModeration/img1").set({thumbUrl: "https://t", cardUrl: "https://c"}, {merge: true});
    await w.db.doc("profiles/member-1").set({
      photos: [{
        id: "img1",
        storagePath,
        downloadUrl,
        thumbUrl: "https://t",
        cardUrl: "https://c",
        order: 0,
        isPrimary: true,
        moderationStatus: "manual_review",
      }],
    }, {merge: true});

    const result = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()});
    assert.equal(result.status, "approved");

    const profile = w.db.read("profiles/member-1");
    const photo = profile.photos[0];
    assert.equal(photo.moderationStatus, "approved");
    assert.equal(photo.storagePath, storagePath);
    assert.equal(photo.downloadUrl, downloadUrl);
    assert.equal(photo.thumbUrl, "https://t");
    assert.equal(photo.cardUrl, "https://c");
    for (const [field, value] of Object.entries(photo)) {
      assert.notEqual(value, undefined, `photos[0].${field} is undefined`);
    }
    assert.equal(profile.profileModerationStatus, "approved");

    const ledger = w.db.read("users/member-1/photoModeration/img1");
    assert.equal(ledger.status, "approved");
    assert.equal(ledger.thumbUrl, "https://t");
    assert.equal(ledger.cardUrl, "https://c");
    assert.equal(ledger.reviewLock, undefined);
    assert.equal(ledger.decisionActionId, result.actionId);
    assert.ok(w.bucket.files.has(storagePath), "the published object is left where it is");
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).type, "PHOTO_APPROVED");
    assert.ok(w.db.paths().some((p) => p.startsWith("adminAuditLog/") && w.db.read(p).action === "PHOTO_APPROVED"));
  });

  it("removing a published photo also deletes its display variants", async () => {
    const w = await world({published: true});
    w.bucket.put("users/member-1/profile/thumbs/img1_thumb.jpg", PORTRAIT);
    w.bucket.put("users/member-1/profile/thumbs/img1_card.jpg", PORTRAIT);
    await w.db.doc("users/member-1/photoModeration/img1").set({thumbUrl: "https://t", cardUrl: "https://c"}, {merge: true});
    await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "reject", reasonCode: "NUDITY_SEXUAL_CONTENT", idempotencyKey: key()});
    assert.equal(w.bucket.files.has("users/member-1/profile/thumbs/img1_thumb.jpg"), false);
    assert.equal(w.bucket.files.has("users/member-1/profile/thumbs/img1_card.jpg"), false);
    const ledger = w.db.read("users/member-1/photoModeration/img1");
    assert.equal(ledger.thumbUrl, null);
    assert.equal(ledger.cardUrl, null);
    const photo = w.db.read("profiles/member-1").photos[0];
    assert.equal(photo.thumbUrl, null);
    assert.equal(photo.cardUrl, null);
  });

  it("a rejected photo stays rejected: no second decision, no client self-approval", async () => {
    const w = await world();
    await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "reject", reasonCode: "LOW_QUALITY", idempotencyKey: key()});
    await rejectsWith(w.run(specs.adminReviewPhotoSpec, "mod-2", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()}), "photo_already_reviewed");
    // A modified client writes "approved" into its own photos array …
    const forged = [{id: "img1", moderationStatus: "approved", moderatedBy: "admin_review", downloadUrl: "https://evil.example/x.png"}];
    await w.db.doc("profiles/member-1").set({photos: forged}, {merge: true});
    await reconcilePhotoModeration(w.db, "member-1");
    // … and reconciliation puts the ledger's decision back.
    assert.equal(w.db.read("profiles/member-1").photos[0].moderationStatus, "rejected");
  });

  it("a client cannot self-approve a photo that is still in review", async () => {
    const w = await world();
    await w.db.doc("profiles/member-1").set({photos: [{id: "img1", moderationStatus: "approved"}]}, {merge: true});
    await reconcilePhotoModeration(w.db, "member-1");
    assert.equal(w.db.read("profiles/member-1").photos[0].moderationStatus, "manual_review");
  });

  it("a double click replays instead of deciding twice", async () => {
    const w = await world();
    const k = key();
    const first = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: k});
    const second = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: k});
    assert.equal(second.replayed, true);
    assert.equal(second.actionId, first.actionId);
    assert.equal(w.db.paths().filter((p) => p.startsWith("moderationActions/")).length, 1);
  });

  it("two reviewers cannot decide the same photo at once", async () => {
    const w = await world();
    await w.db.doc("users/member-1/photoModeration/img1").set({
      reviewLock: {token: require("../lib/admin/photos/photoReview.js").reviewerToken("mod-1"), at: new Date(w.now)},
    }, {merge: true});
    await rejectsWith(
      w.run(specs.adminReviewPhotoSpec, "mod-2", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()}),
      "photo_review_in_progress",
    );
    const queue = await w.run(specs.adminListPhotoReviewsSpec, "mod-2", {});
    assert.equal(queue.items[0].lock, "another_reviewer");
  });

  it("escalation opens a PHOTO_REVIEW case and leaves the ledger untouched", async () => {
    const w = await world();
    const result = await w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision: "escalate", reasonCode: "MINOR_IN_PHOTO", idempotencyKey: key()});
    const c = w.db.read(`moderationCases/${result.caseId}`);
    assert.equal(c.type, "PHOTO_REVIEW");
    assert.equal(c.priority, "high");
    assert.equal(w.db.read("users/member-1/photoModeration/img1").status, "manual_review");
  });

  it("support agents cannot see or decide photos", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminListPhotoReviewsSpec, "support-1", {}), "permission_denied");
    await rejectsWith(w.run(specs.adminReviewPhotoSpec, "support-1", {uid: "member-1", imageId: "img1", decision: "approve", idempotencyKey: key()}), "permission_denied");
  });
});

const PUBLISHED = "users/member-1/profile/photos/img1.png";
const PENDING = "users/member-1/profile/pending/img1.png";
const THUMB = "users/member-1/profile/thumbs/img1_thumb.jpg";
const CARD = "users/member-1/profile/thumbs/img1_card.jpg";
const QUARANTINED = "moderation/quarantine/member-1/img1.png";

const photosOf = (w) => w.db.read("profiles/member-1").photos;
const ledgerOf = (w) => w.db.read("users/member-1/photoModeration/img1");
const storedOf = (w) => [...w.bucket.files.keys()].filter((p) => p.includes("/img1")).sort();
const actionsOf = (w) => w.db.paths().filter((p) => p.startsWith("moderationActions/"));
const decide = (w, decision, extra = {}) =>
  w.run(specs.adminReviewPhotoSpec, "mod-1", {uid: "member-1", imageId: "img1", decision, idempotencyKey: key(), ...extra});

/** A published photo is stored the way the pipeline leaves it: with its variants and its upload. */
async function storedWorld(options = {}) {
  const w = await world(options);
  if (options.published) {
    w.bucket.put(PENDING, PNG, "image/png");
    w.bucket.put(THUMB, PORTRAIT);
    w.bucket.put(CARD, PORTRAIT);
  }
  return w;
}

/** The member removes the photo through the server while it is under review. */
async function memberRemoved(options = {}) {
  const w = await storedWorld(options);
  const result = await deleteProfilePhoto({db: w.db, bucket: () => w.bucket, now: () => w.now}, "member-1", {photoId: "img1"});
  assert.deepEqual(result, {photoId: "img1", removed: true, cleanup: "retained"});
  assert.deepEqual(photosOf(w), []);
  return w;
}

describe("admin photo review — a photo the member removed is not put back", () => {
  it("the queue shows the reviewer that the photo is off the profile", async () => {
    const onProfile = await world({published: true});
    const before = (await onProfile.run(specs.adminListPhotoReviewsSpec, "mod-1", {filter: "manual_review"})).items[0];
    assert.equal(before.onProfile, true);
    assert.equal(before.removedByMember, false);

    const w = await memberRemoved({published: true});
    const after = (await w.run(specs.adminListPhotoReviewsSpec, "mod-1", {filter: "manual_review"})).items[0];
    assert.equal(after.onProfile, false);
    assert.equal(after.removedByMember, true);
  });

  it("the image is still there for the reviewer until the decision", async () => {
    const w = await memberRemoved({published: true});
    const preview = await w.run(specs.adminGetPhotoPreviewSpec, "mod-1", {uid: "member-1", imageId: "img1"});
    assert.equal(preview.source, "published");
  });

  it("approving it deletes what was kept instead of restoring the photo", async () => {
    const w = await memberRemoved({published: true});
    const result = await decide(w, "approve");
    assert.equal(result.status, "approved");
    assert.equal(result.placement, "removed_by_member");
    assert.deepEqual(photosOf(w), []);
    assert.equal(ledgerOf(w), undefined);
    assert.deepEqual(storedOf(w), []);
    assert.equal(w.db.read("profiles/member-1").profileModerationStatus, "approved");
  });

  it("the approval is still on record: action, audit event, replay", async () => {
    const w = await memberRemoved({published: true});
    const k = key();
    const result = await decide(w, "approve", {idempotencyKey: k});
    const action = w.db.read(`moderationActions/${result.actionId}`);
    assert.equal(action.type, "PHOTO_APPROVED");
    assert.deepEqual(action.previousState, {status: "manual_review"});
    assert.deepEqual(action.newState, {status: "approved", placement: "removed_by_member"});
    const audit = w.db.paths().map((p) => (p.startsWith("adminAuditLog/") ? w.db.read(p) : null))
      .find((event) => event?.action === "PHOTO_APPROVED");
    assert.equal(audit.metadata.placement, "removed_by_member");

    const again = await decide(w, "approve", {idempotencyKey: k});
    assert.equal(again.replayed, true);
    assert.equal(again.actionId, result.actionId);
    assert.equal(again.placement, "removed_by_member");
    assert.equal(actionsOf(w).length, 1);
    // The decision does not leave a stub where the entry was.
    assert.equal(ledgerOf(w), undefined);
  });

  it("a photo that was never published is not published on the way out", async () => {
    const w = await memberRemoved();
    assert.deepEqual(storedOf(w), [PENDING]);
    const result = await decide(w, "approve");
    assert.equal(result.placement, "removed_by_member");
    assert.deepEqual(storedOf(w), []);
    assert.deepEqual(photosOf(w), []);
    assert.equal(ledgerOf(w), undefined);
  });

  it("reconciliation afterwards has nothing to put back", async () => {
    const w = await memberRemoved({published: true});
    await decide(w, "approve");
    assert.equal(await reconcilePhotoModeration(w.db, "member-1", w.bucket), false);
    assert.deepEqual(photosOf(w), []);
  });

  it("a verified photo removed while it was held is not restored as the Face Anchor", async () => {
    const w = await storedWorld({published: true});
    await w.db.doc("users/member-1/photoModeration/img1").set({
      faceAnchor: {status: "verified", verifiedAt: Timestamp.fromMillis(w.now), provider: "test", attemptId: "a1", storagePath: PUBLISHED},
    }, {merge: true});
    await deleteProfilePhoto({db: w.db, bucket: () => w.bucket, now: () => w.now}, "member-1", {photoId: "img1"});
    await decide(w, "approve");
    await reconcilePhotoModeration(w.db, "member-1", w.bucket);
    assert.deepEqual(photosOf(w), []);
    assert.deepEqual(w.db.read("profiles/member-1").faceAnchorPhotoIds ?? [], []);
  });

  it("an id a stale array write put back goes again with the approval", async () => {
    const w = await memberRemoved({published: true});
    await w.db.doc("profiles/member-1").set({
      photos: [{id: "img1", storagePath: PUBLISHED, order: 0, isPrimary: true, moderationStatus: "manual_review"}],
    }, {merge: true});
    await decide(w, "approve");
    assert.deepEqual(photosOf(w), []);
    assert.equal(ledgerOf(w), undefined);
    assert.deepEqual(storedOf(w), []);
  });

  it("rejecting it quarantines the image and adds no rejected photo to the profile", async () => {
    const w = await memberRemoved({published: true});
    const result = await decide(w, "reject", {reasonCode: "NUDITY_SEXUAL_CONTENT"});
    assert.equal(result.status, "rejected");
    assert.equal(result.placement, "removed_by_member");
    assert.deepEqual(photosOf(w), []);
    const ledger = ledgerOf(w);
    assert.equal(ledger.status, "rejected");
    assert.ok(ledger.removedByMemberAt, "the record still says the member removed it");
    assert.ok(w.bucket.files.has(QUARANTINED));
    assert.equal(w.bucket.files.has(PUBLISHED), false);
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).type, "PHOTO_REMOVED");
    assert.equal(await reconcilePhotoModeration(w.db, "member-1", w.bucket), false);
    assert.deepEqual(photosOf(w), []);
  });

  describe("when Storage will not delete an object", () => {
    function failingOn(w, path) {
      const file = w.bucket.file.bind(w.bucket);
      let failing = true;
      w.bucket.file = (name) => {
        const handle = file(name);
        if (name !== path) return handle;
        return {
          ...handle,
          async delete() {
            if (failing) throw new Error("storage unavailable");
            return handle.delete();
          },
        };
      };
      return () => {
        failing = false;
      };
    }

    it("the approval fails, the photo stays in the queue, and deciding again finishes", async () => {
      const w = await memberRemoved({published: true});
      const recover = failingOn(w, PUBLISHED);
      await rejectsWith(decide(w, "approve"), "internal_error");
      assert.equal(ledgerOf(w).status, "manual_review");
      assert.equal(ledgerOf(w).reviewLock, undefined);
      assert.deepEqual(actionsOf(w), []);
      assert.deepEqual(storedOf(w), [PUBLISHED]);
      const queue = await w.run(specs.adminListPhotoReviewsSpec, "mod-1", {filter: "manual_review"});
      assert.equal(queue.items.length, 1);

      recover();
      const result = await decide(w, "approve");
      assert.equal(result.placement, "removed_by_member");
      assert.equal(ledgerOf(w), undefined);
      assert.deepEqual(storedOf(w), []);
      assert.equal(actionsOf(w).length, 1);
    });
  });
});

describe("admin photo review — a decision never adds a photo to a profile", () => {
  /** What an older client leaves: the id gone from the array, nothing said to the server. */
  async function arrayRewritten(options = {}) {
    const w = await storedWorld(options);
    await w.db.doc("profiles/member-1").set({photos: []}, {merge: true});
    return w;
  }

  it("a photo that is on the profile takes the decision, as before", async () => {
    const w = await world();
    const result = await decide(w, "approve");
    assert.equal(result.placement, "on_profile");
    assert.equal(photosOf(w)[0].moderationStatus, "approved");
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).newState.placement, "on_profile");
  });

  it("approving a photo that is not in the array records the decision and adds nothing", async () => {
    const w = await arrayRewritten({published: true});
    const result = await decide(w, "approve");
    assert.equal(result.status, "approved");
    assert.equal(result.placement, "not_on_profile");
    assert.deepEqual(photosOf(w), []);
    assert.equal(ledgerOf(w).status, "approved");
    assert.equal(w.db.read("profiles/member-1").profileModerationStatus, "approved");
  });

  it("and deletes nothing: absence alone is not proof the member removed it", async () => {
    const w = await arrayRewritten({published: true});
    const before = storedOf(w);
    await decide(w, "approve");
    assert.deepEqual(storedOf(w), before);
    assert.ok(w.bucket.files.has(PUBLISHED));
  });

  it("rejecting one adds no rejected photo either", async () => {
    const w = await arrayRewritten({published: true});
    const result = await decide(w, "reject", {reasonCode: "NUDITY_SEXUAL_CONTENT"});
    assert.equal(result.placement, "not_on_profile");
    assert.deepEqual(photosOf(w), []);
    assert.equal(ledgerOf(w).status, "rejected");
    assert.ok(w.bucket.files.has(QUARANTINED));
  });

  it("rejecting an approved photo the member no longer shows adds nothing", async () => {
    const w = await arrayRewritten({published: true});
    await w.db.doc("users/member-1/photoModeration/img1").set({status: "approved", moderatedBy: "system"}, {merge: true});
    await decide(w, "reject", {reasonCode: "NUDITY_SEXUAL_CONTENT"});
    assert.deepEqual(photosOf(w), []);
  });
});
