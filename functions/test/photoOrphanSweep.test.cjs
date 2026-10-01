const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {Timestamp} = require("firebase-admin/firestore");
const {
  UNREFERENCED_GRACE_MS,
  photoOrphanSweepModeFrom,
  stampUnreferencedPhotos,
  sweepUnreferencedPhotos,
} = require("../lib/moderation/photoOrphanSweep.js");
const {deleteProfilePhoto} = require("../lib/moderation/deleteProfilePhoto.js");
const {profileNeedsReconciling} = require("../lib/moderation/photoInvariants.js");
const {
  reconcilePhotoModeration,
  setPhotoModerationStatus,
} = require("../lib/moderation/photoModerationService.js");
const {variantPath} = require("../lib/moderation/photoVariants.js");
const {PROCESSING_STALE_MS} = require("../lib/moderation/types.js");
const {
  JPEG,
  T0,
  createFaceAnchorWorld,
  publishedPath,
  verdict,
} = require("./helpers/faceAnchorHarness.cjs");

const UID = "member-1";
const FOUR = ["p1", "p2", "p3", "p4"];
const DAY_MS = 24 * 60 * 60 * 1000;

const pendingPath = (id, uid = UID) => `users/${uid}/profile/pending/${id}.jpg`;
const ledgerPath = (id, uid = UID) => `users/${uid}/photoModeration/${id}`;

/** Stores a photo the way the pipeline leaves it: original, variants, upload. */
function store(w, id, uid = UID) {
  w.bucket.put(publishedPath(uid, id), JPEG(`photo-${id}`));
  w.bucket.put(pendingPath(id, uid), JPEG(`pending-${id}`));
  w.bucket.put(variantPath(uid, id, "thumb"), JPEG(`thumb-${id}`));
  w.bucket.put(variantPath(uid, id, "card"), JPEG(`card-${id}`));
}

function world(options = {}) {
  const w = createFaceAnchorWorld({
    photos: FOUR,
    ...options,
    profile: {profileCompleted: true, ...(options.profile ?? {})},
  });
  for (const id of options.photos ?? FOUR) {
    store(w, id);
  }
  return w;
}

/** A second member in the same database, with photos and already-stamped orphans. */
async function addMember(w, uid, {photos = ["a1", "a2", "a3"], orphans = {}} = {}) {
  await w.db.doc(`profiles/${uid}`).set({
    uid,
    profileCompleted: true,
    photos: photos.map((id, index) => ({
      id,
      order: index,
      isPrimary: index === 0,
      moderationStatus: "approved",
      storagePath: publishedPath(uid, id),
      downloadUrl: `https://cdn.test/${id}.jpg`,
    })),
  });
  const entry = (id) => ({
    imageId: id,
    status: "approved",
    storagePath: publishedPath(uid, id),
    downloadUrl: `https://cdn.test/${id}.jpg`,
    moderatedBy: "system",
  });
  for (const id of photos) {
    await w.db.doc(ledgerPath(id, uid)).set(entry(id));
    store(w, id, uid);
  }
  for (const [id, sinceMs] of Object.entries(orphans)) {
    await w.db.doc(ledgerPath(id, uid)).set({...entry(id), unreferencedSince: Timestamp.fromMillis(sinceMs)});
    store(w, id, uid);
  }
}

/** What an app without deleteProfilePhoto does: writes the array without the photo. */
async function writeArrayWithout(w, ...removed) {
  const photos = w.profile().photos.filter((photo) => !removed.includes(photo.id));
  await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});
}

/** The same, followed by the reconciliation the profile trigger runs. */
async function oldClientRemoves(w, ...removed) {
  await writeArrayWithout(w, ...removed);
  return reconcilePhotoModeration(w.db, UID, w.bucket);
}

function sweep(w, at, options = {}) {
  return sweepUnreferencedPhotos({db: w.db, bucket: () => w.bucket, now: () => at}, options);
}

const ids = (w) => w.profile().photos.map((photo) => photo.id);
const stamp = (w, id, uid = UID) => w.db.read(ledgerPath(id, uid))?.unreferencedSince;
/** The first moment the sweep may act on this photo. */
const dueAt = (w, id) => stamp(w, id).toMillis() + UNREFERENCED_GRACE_MS;
const storedFor = (w, id, uid = UID) =>
  [...w.bucket.files.keys()].filter((name) => name.startsWith(`users/${uid}/`) && name.includes(`/${id}`));

describe("a photo that leaves the array is marked, not deleted", () => {
  it("stamps the ledger entry and leaves everything stored", async () => {
    const w = world();
    // The fixture's photos first take their moderation fields from the ledger.
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    const changed = await oldClientRemoves(w, "p2");
    assert.equal(changed, false, "a stamp is not a profile change");
    assert.ok(stamp(w, "p2"));
    assert.equal(w.ledger("p2").status, "approved");
    assert.equal(storedFor(w, "p2").length, 4);
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("stamps nothing that is still on the profile", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    for (const id of ["p1", "p3", "p4"]) {
      assert.equal(stamp(w, id), undefined, id);
    }
  });

  it("the stamp says since when, so a later pass does not move it", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const first = stamp(w, "p2").toMillis();
    w.db.resetStats();
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    assert.equal(w.db.stats().writes, 0);
    assert.equal(stamp(w, "p2").toMillis(), first);
  });

  it("leaves updatedAt alone: it is the entry's place in the review queue", async () => {
    const queued = Timestamp.fromMillis(T0 - DAY_MS);
    const w = world({ledger: {p2: {status: "pending", updatedAt: queued}}});
    await oldClientRemoves(w, "p2");
    assert.ok(stamp(w, "p2"));
    assert.equal(w.ledger("p2").updatedAt.toMillis(), queued.toMillis());
  });

  it("an id that comes back loses the stamp", async () => {
    const w = world();
    const before = w.profile().photos;
    await oldClientRemoves(w, "p2");
    // The next write still had the photo: a stale whole-array write undone.
    await w.db.doc(`profiles/${UID}`).set({photos: before}, {merge: true});
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    assert.equal(stamp(w, "p2"), undefined);
    assert.equal(w.ledger("p2").status, "approved");
  });

  it("a photo moderation rejected or is holding is never stamped", async () => {
    const w = world({ledger: {p2: {status: "rejected"}, p3: {status: "manual_review"}}});
    await oldClientRemoves(w, "p2", "p3");
    assert.equal(stamp(w, "p2"), undefined);
    assert.equal(stamp(w, "p3"), undefined);
  });

  it("a stamped photo that is pulled into review loses the stamp", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    await w.db.doc(ledgerPath("p2")).update({status: "manual_review"});
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    assert.equal(stamp(w, "p2"), undefined);
  });

  it("pending and processing uploads that left the array are stamped too", async () => {
    const w = world({ledger: {p2: {status: "pending"}, p3: {status: "processing"}}});
    await oldClientRemoves(w, "p2", "p3");
    assert.ok(stamp(w, "p2"));
    assert.ok(stamp(w, "p3"));
  });

  it("a removed last Face Anchor is put back and not stamped", async () => {
    const w = world({ledger: {p1: {faceAnchor: verdict(UID, "p1")}}});
    await oldClientRemoves(w, "p1");
    assert.deepEqual(ids(w)[0], "p1");
    assert.equal(stamp(w, "p1"), undefined);
  });

  it("an anchor given up for another one is stamped like any other photo", async () => {
    const w = world({
      ledger: {
        p1: {faceAnchor: verdict(UID, "p1")},
        p2: {faceAnchor: verdict(UID, "p2", {verifiedAtMs: T0 + 1000})},
      },
    });
    await oldClientRemoves(w, "p2");
    assert.equal(w.ledger("p2").faceAnchor, undefined);
    assert.ok(stamp(w, "p2"));
  });

  it("a photo deleted through the callable leaves nothing to stamp", async () => {
    const w = world();
    await deleteProfilePhoto({db: w.db, bucket: () => w.bucket, now: () => w.now}, UID, {photoId: "p2"});
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
  });

  it("the member emptying the array is still a write to reconcile", () => {
    const photo = {id: "p1"};
    assert.equal(profileNeedsReconciling({photos: [photo]}, {photos: []}), true);
    assert.equal(profileNeedsReconciling({photos: [photo]}, {}), true);
    assert.equal(profileNeedsReconciling(undefined, {photos: [photo]}), true);
    assert.equal(profileNeedsReconciling({photos: []}, {photos: [], faceAnchorPhotoIds: ["p1"]}), true);
    // A profile that had no photos and has none: nothing to do.
    assert.equal(profileNeedsReconciling(undefined, {photos: []}), false);
    assert.equal(profileNeedsReconciling({photos: []}, {displayName: "Member"}), false);
  });
});

describe("a review decision about a photo that is on no profile", () => {
  it("an approval is stamped there and then: no profile write will follow", async () => {
    const w = world({ledger: {p2: {status: "manual_review"}}});
    await oldClientRemoves(w, "p2");
    assert.equal(stamp(w, "p2"), undefined);
    const result = await setPhotoModerationStatus(
      w.db, UID, "p2", {moderationStatus: "approved", moderatedBy: "admin_review"}, {whenAbsent: "skip"});
    assert.deepEqual(result, {onProfile: false});
    assert.ok(stamp(w, "p2"));
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("a rejection is a record and is not stamped", async () => {
    const w = world({ledger: {p2: {status: "manual_review"}}});
    await oldClientRemoves(w, "p2");
    await setPhotoModerationStatus(
      w.db, UID, "p2", {moderationStatus: "rejected", moderatedBy: "admin_review"}, {whenAbsent: "skip"});
    assert.equal(stamp(w, "p2"), undefined);
  });

  it("a second decision does not move the stamp", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const first = stamp(w, "p2").toMillis();
    await setPhotoModerationStatus(
      w.db, UID, "p2", {moderationStatus: "approved", moderatedBy: "admin_review"}, {whenAbsent: "skip"});
    assert.equal(stamp(w, "p2").toMillis(), first);
  });
});

describe("the sweep waits out the grace period", () => {
  it("the grace period is seven days", () => {
    assert.equal(UNREFERENCED_GRACE_MS, 7 * DAY_MS);
  });

  it("does nothing a moment before it", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const result = await sweep(w, dueAt(w, "p2") - 1);
    assert.deepEqual(
      result,
      {mode: "delete", scanned: 0, members: 0, deleted: 0, incomplete: 0, failed: 0, capped: false});
    assert.equal(w.ledger("p2").status, "approved");
    assert.equal(storedFor(w, "p2").length, 4);
  });

  it("then deletes the entry, the original, both variants and the upload", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const result = await sweep(w, dueAt(w, "p2"));
    assert.deepEqual(
      result,
      {mode: "delete", scanned: 1, members: 1, deleted: 1, incomplete: 0, failed: 0, capped: false});
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
  });

  it("touches nothing else of the member", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const profile = JSON.stringify(w.profile());
    await sweep(w, dueAt(w, "p2"));
    assert.equal(JSON.stringify(w.profile()), profile);
    for (const id of ["p1", "p3", "p4"]) {
      assert.equal(w.ledger(id).status, "approved", id);
      assert.equal(storedFor(w, id).length, 4, id);
    }
  });

  it("a published object under another extension goes too", async () => {
    const w = world({ledger: {p2: {storagePath: `users/${UID}/profile/photos/p2.png`}}});
    w.bucket.put(`users/${UID}/profile/photos/p2.png`, JPEG("png"));
    await oldClientRemoves(w, "p2");
    await sweep(w, dueAt(w, "p2"));
    assert.deepEqual(storedFor(w, "p2"), []);
  });

  it("several orphans of one member go in one pass", async () => {
    const w = world({photos: ["p1", "p2", "p3", "p4", "p5"]});
    await oldClientRemoves(w, "p2", "p5");
    const result = await sweep(w, Math.max(dueAt(w, "p2"), dueAt(w, "p5")));
    assert.equal(result.scanned, 2);
    assert.equal(result.members, 1);
    assert.equal(result.deleted, 2);
    assert.equal(w.ledger("p2"), undefined);
    assert.equal(w.ledger("p5"), undefined);
  });

  it("an upload that never got past pending is collected as well", async () => {
    const w = world({ledger: {p2: {status: "pending", storagePath: pendingPath("p2")}}});
    await oldClientRemoves(w, "p2");
    await sweep(w, dueAt(w, "p2"));
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
  });

  it("a second run finds nothing left to do", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const at = dueAt(w, "p2");
    await sweep(w, at);
    const again = await sweep(w, at + DAY_MS);
    assert.equal(again.scanned, 0);
    assert.equal(again.deleted, 0);
  });
});

describe("the sweep checks again before it deletes", () => {
  /** Stamped long ago, whatever the profile says now. */
  const longAgo = Timestamp.fromMillis(T0 - 30 * DAY_MS);

  it("a photo that is back on the profile is kept and its stamp cleared", async () => {
    // The stamp outlived the photo's return: the reconciliation that would
    // have cleared it never ran.
    const w = world({ledger: {p2: {unreferencedSince: longAgo}}});
    const result = await sweep(w, T0);
    assert.equal(result.scanned, 1);
    assert.equal(result.deleted, 0);
    assert.equal(w.ledger("p2").status, "approved");
    assert.equal(stamp(w, "p2"), undefined);
    assert.equal(storedFor(w, "p2").length, 4);
    assert.deepEqual(ids(w), FOUR);
  });

  it("a last Face Anchor missing from the array is put back, not deleted", async () => {
    const w = world({ledger: {p1: {faceAnchor: verdict(UID, "p1"), unreferencedSince: longAgo}}});
    await writeArrayWithout(w, "p1");
    const result = await sweep(w, T0);
    assert.equal(result.deleted, 0);
    assert.equal(ids(w)[0], "p1");
    assert.equal(stamp(w, "p1"), undefined);
    assert.equal(storedFor(w, "p1").length, 4);
  });

  it("judges absence on the array the rules produce, even with nothing reconciled", async () => {
    // A dry run does not reconcile first, so this is the transaction's own
    // check: the stored array lacks the anchor, the rules would restore it.
    const w = world({ledger: {p1: {faceAnchor: verdict(UID, "p1"), unreferencedSince: longAgo}}});
    await writeArrayWithout(w, "p1");
    const result = await sweep(w, T0, {mode: "dry-run"});
    assert.equal(result.scanned, 1);
    assert.equal(result.deleted, 0);
  });

  it("a stale stamp on a photo that is on the profile is not a reason to delete", async () => {
    // Dry run, so nothing has cleared the stamp: the transaction alone decides.
    const w = world({ledger: {p2: {unreferencedSince: longAgo}}});
    const result = await sweep(w, T0, {mode: "dry-run"});
    assert.equal(result.scanned, 1);
    assert.equal(result.deleted, 0);
  });

  it("a photo written back while the sweep is on its member is kept", async () => {
    const w = world();
    const before = w.profile().photos;
    await oldClientRemoves(w, "p2");
    const at = dueAt(w, "p2");
    const runTransaction = w.db.runTransaction.bind(w.db);
    let calls = 0;
    w.db.runTransaction = async (fn) => {
      const result = await runTransaction(fn);
      calls += 1;
      if (calls === 1) {
        // After the sweep's reconciliation, before its delete transaction.
        await w.db.doc(`profiles/${UID}`).set({photos: before}, {merge: true});
      }
      return result;
    };
    const result = await sweep(w, at);
    assert.equal(result.deleted, 0);
    assert.equal(w.ledger("p2").status, "approved");
    assert.equal(storedFor(w, "p2").length, 4);
  });

  it("an entry that still holds a Face Anchor verdict is not deleted", async () => {
    // Two anchors, one missing from the array, and no reconciliation has given
    // its verdict up yet. A dry run does not reconcile, so this is the
    // transaction's own refusal.
    const w = world({
      ledger: {
        p1: {faceAnchor: verdict(UID, "p1")},
        p2: {faceAnchor: verdict(UID, "p2", {verifiedAtMs: T0 + 1000}), unreferencedSince: longAgo},
      },
    });
    await writeArrayWithout(w, "p2");
    const result = await sweep(w, T0, {mode: "dry-run"});
    assert.equal(result.scanned, 1);
    assert.equal(result.deleted, 0);
  });

  it("a moderation record is kept even if it carries a stamp", async () => {
    const w = world({
      ledger: {
        p2: {status: "rejected", unreferencedSince: longAgo},
        p3: {status: "manual_review", unreferencedSince: longAgo},
      },
    });
    await writeArrayWithout(w, "p2", "p3");
    for (const mode of ["dry-run", "delete"]) {
      const result = await sweep(w, T0, {mode});
      assert.equal(result.deleted, 0, mode);
    }
    assert.equal(w.ledger("p2").status, "rejected");
    assert.equal(w.ledger("p3").status, "manual_review");
    assert.equal(storedFor(w, "p2").length, 4);
    assert.equal(storedFor(w, "p3").length, 4);
  });

  it("a photo the pipeline is on right now is left for the next run", async () => {
    const w = world({ledger: {p2: {status: "processing"}}});
    await oldClientRemoves(w, "p2");
    const at = dueAt(w, "p2");
    await w.db.doc(ledgerPath("p2")).update({moderatedAt: Timestamp.fromMillis(at - 60 * 1000)});
    const result = await sweep(w, at);
    assert.equal(result.deleted, 0);
    assert.equal(w.ledger("p2").status, "processing");
    assert.equal(storedFor(w, "p2").length, 4);
  });

  it("a processing run that died is collected", async () => {
    const w = world({ledger: {p2: {status: "processing"}}});
    await oldClientRemoves(w, "p2");
    const at = dueAt(w, "p2");
    await w.db.doc(ledgerPath("p2")).update({moderatedAt: Timestamp.fromMillis(at - PROCESSING_STALE_MS)});
    const result = await sweep(w, at);
    assert.equal(result.deleted, 1);
    assert.equal(w.ledger("p2"), undefined);
  });

  it("entries of an account with no profile are left alone", async () => {
    const w = world();
    await w.db.doc(ledgerPath("gone", "ghost")).set({
      imageId: "gone",
      status: "approved",
      storagePath: publishedPath("ghost", "gone"),
      unreferencedSince: longAgo,
    });
    store(w, "gone", "ghost");
    const result = await sweep(w, T0);
    assert.equal(result.scanned, 1);
    assert.equal(result.deleted, 0);
    assert.equal(w.db.read(ledgerPath("gone", "ghost")).status, "approved");
    assert.equal(storedFor(w, "gone", "ghost").length, 4);
  });

  it("an id written back after the sweep is an unmoderated photo, not the old one", async () => {
    const w = world();
    const before = w.profile().photos;
    await oldClientRemoves(w, "p2");
    await sweep(w, dueAt(w, "p2"));
    // A device that was offline all along writes its old array.
    await w.db.doc(`profiles/${UID}`).set({photos: before}, {merge: true});
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    const returned = w.profile().photos.find((photo) => photo.id === "p2");
    assert.equal(returned.moderationStatus, "pending");
    assert.equal(w.ledger("p2"), undefined);
  });
});

describe("when Storage will not delete an object", () => {
  function failingOn(w, name) {
    const file = w.bucket.file.bind(w.bucket);
    w.bucket.file = (candidate) => {
      const handle = file(candidate);
      if (candidate !== name) {
        return handle;
      }
      return {
        ...handle,
        async delete() {
          throw new Error("storage unavailable");
        },
      };
    };
  }

  it("the run reports the photo as incomplete and carries on", async () => {
    const w = world({photos: ["p1", "p2", "p3", "p4", "p5"]});
    await oldClientRemoves(w, "p2", "p5");
    failingOn(w, publishedPath(UID, "p2"));
    const result = await sweep(w, Math.max(dueAt(w, "p2"), dueAt(w, "p5")));
    assert.equal(result.incomplete, 1);
    assert.equal(result.deleted, 1);
    // The entry went with the transaction; only the one object is left.
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), [publishedPath(UID, "p2")]);
    assert.deepEqual(storedFor(w, "p5"), []);
  });
});

describe("the sweep's switch", () => {
  it("reads the setting", () => {
    assert.equal(photoOrphanSweepModeFrom(undefined), "delete");
    assert.equal(photoOrphanSweepModeFrom(""), "delete");
    assert.equal(photoOrphanSweepModeFrom(" ON "), "delete");
    assert.equal(photoOrphanSweepModeFrom("off"), "off");
    assert.equal(photoOrphanSweepModeFrom("dry-run"), "dry-run");
  });

  it("a word it does not know stops the deleting", () => {
    assert.equal(photoOrphanSweepModeFrom("of"), "dry-run");
    assert.equal(photoOrphanSweepModeFrom("false"), "dry-run");
  });

  it("a dry run reports what would go and writes nothing", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const at = dueAt(w, "p2");
    w.db.resetStats();
    const result = await sweep(w, at, {mode: "dry-run"});
    assert.deepEqual(
      result,
      {mode: "dry-run", scanned: 1, members: 1, deleted: 1, incomplete: 0, failed: 0, capped: false});
    assert.equal(w.db.stats().writes, 0);
    assert.deepEqual(w.bucket.deletes, []);
    assert.ok(stamp(w, "p2"));
  });

  it("off does not even look", async () => {
    const w = world();
    await oldClientRemoves(w, "p2");
    const at = dueAt(w, "p2");
    w.db.resetStats();
    const result = await sweep(w, at, {mode: "off"});
    assert.equal(result.scanned, 0);
    assert.deepEqual(w.db.stats(), {...w.db.stats(), reads: 0, writes: 0});
    assert.equal(storedFor(w, "p2").length, 4);
  });
});

describe("a run across many members", () => {
  const old = (days) => T0 - days * DAY_MS;

  async function three() {
    const w = world();
    await addMember(w, "member-a", {orphans: {x1: old(30)}});
    await addMember(w, "member-b", {orphans: {x1: old(20), x2: old(19)}});
    await addMember(w, "member-c", {orphans: {x1: old(10)}});
    return w;
  }

  it("collects every member's orphans, oldest first, across pages", async () => {
    const w = await three();
    const result = await sweep(w, T0, {pageSize: 1});
    // member-b's second orphan went with its first and was never read.
    assert.equal(result.scanned, 3);
    assert.equal(result.members, 3);
    assert.equal(result.deleted, 4);
    for (const uid of ["member-a", "member-b", "member-c"]) {
      assert.deepEqual(storedFor(w, "x1", uid), [], uid);
      assert.equal(storedFor(w, "a1", uid).length, 4, uid);
    }
    assert.deepEqual(storedFor(w, "x2", "member-b"), []);
  });

  it("a dry run pages through the same entries without deleting them", async () => {
    const w = await three();
    const result = await sweep(w, T0, {mode: "dry-run", pageSize: 1});
    assert.equal(result.scanned, 4);
    assert.equal(result.deleted, 4);
    assert.equal(storedFor(w, "x1", "member-a").length, 4);
  });

  it("stops at the per-run limit and leaves the rest for the next run", async () => {
    const w = await three();
    const first = await sweep(w, T0, {maxMembers: 2});
    assert.equal(first.capped, true);
    assert.equal(first.members, 2);
    assert.equal(first.deleted, 3);
    // Oldest first: the member stamped most recently is the one that waits.
    assert.equal(storedFor(w, "x1", "member-c").length, 4);
    const second = await sweep(w, T0, {maxMembers: 2});
    assert.equal(second.capped, false);
    assert.equal(second.deleted, 1);
    assert.deepEqual(storedFor(w, "x1", "member-c"), []);
  });

  it("one member failing does not stop the others", async () => {
    const w = await three();
    const runTransaction = w.db.runTransaction.bind(w.db);
    let calls = 0;
    w.db.runTransaction = (fn) => {
      calls += 1;
      // The first transaction of the run is member-a's reconciliation.
      return calls === 1 ? Promise.reject(new Error("aborted")) : runTransaction(fn);
    };
    const result = await sweep(w, T0);
    assert.equal(result.failed, 1);
    assert.equal(result.deleted, 3);
    assert.equal(storedFor(w, "x1", "member-a").length, 4);
  });

  it("a photo not yet due is not swept along with its member's older one", async () => {
    const w = world();
    await addMember(w, "member-a", {orphans: {x1: old(30), x2: old(1)}});
    const result = await sweep(w, T0);
    assert.equal(result.deleted, 1);
    assert.deepEqual(storedFor(w, "x1", "member-a"), []);
    assert.equal(storedFor(w, "x2", "member-a").length, 4);
  });
});

describe("catching up profiles nobody has written since", () => {
  it("stamps an orphan without touching the profile", async () => {
    const w = world();
    await writeArrayWithout(w, "p2");
    const profile = JSON.stringify(w.profile());
    const result = await stampUnreferencedPhotos(w.db, UID);
    assert.deepEqual(result, {stamped: ["p2"], cleared: []});
    assert.ok(stamp(w, "p2"));
    assert.equal(JSON.stringify(w.profile()), profile);
  });

  it("a dry run only says what it would stamp", async () => {
    const w = world();
    await writeArrayWithout(w, "p2");
    w.db.resetStats();
    const result = await stampUnreferencedPhotos(w.db, UID, {dryRun: true});
    assert.deepEqual(result, {stamped: ["p2"], cleared: []});
    assert.equal(w.db.stats().writes, 0);
    assert.equal(stamp(w, "p2"), undefined);
  });

  it("is done once: a second pass has nothing to add", async () => {
    const w = world();
    await writeArrayWithout(w, "p2");
    await stampUnreferencedPhotos(w.db, UID);
    assert.deepEqual(await stampUnreferencedPhotos(w.db, UID), {stamped: [], cleared: []});
  });

  it("does not stamp a last Face Anchor that reconciliation would put back", async () => {
    const w = world({ledger: {p1: {faceAnchor: verdict(UID, "p1")}}});
    await writeArrayWithout(w, "p1");
    assert.deepEqual(await stampUnreferencedPhotos(w.db, UID), {stamped: [], cleared: []});
  });

  it("what it stamps still waits out the grace period", async () => {
    const w = world();
    await writeArrayWithout(w, "p2");
    await stampUnreferencedPhotos(w.db, UID);
    const early = await sweep(w, dueAt(w, "p2") - 1);
    assert.equal(early.deleted, 0);
    const result = await sweep(w, dueAt(w, "p2"));
    assert.equal(result.deleted, 1);
  });

  it("an account without a profile is skipped", async () => {
    const w = world();
    assert.deepEqual(await stampUnreferencedPhotos(w.db, "nobody"), {stamped: [], cleared: []});
  });
});

describe("the index the sweep's query needs", () => {
  it("is declared for the collection group", () => {
    const file = path.join(__dirname, "..", "..", "firebase", "firestore.indexes.json");
    const {fieldOverrides} = JSON.parse(fs.readFileSync(file, "utf8"));
    const override = fieldOverrides.find((entry) =>
      entry.collectionGroup === "photoModeration" && entry.fieldPath === "unreferencedSince");
    assert.ok(override, "no field override for photoModeration.unreferencedSince");
    assert.ok(override.indexes.some((index) =>
      index.queryScope === "COLLECTION_GROUP" && index.order === "ASCENDING"));
  });
});
