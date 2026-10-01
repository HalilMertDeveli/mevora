const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
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
