const {afterEach, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {
  deleteProfilePhoto,
  photoObjectPaths,
  photosWithout,
} = require("../lib/moderation/deleteProfilePhoto.js");
const {
  processPendingProfilePhoto,
  reconcilePhotoModeration,
  setPhotoModerationStatus,
} = require("../lib/moderation/photoModerationService.js");
const {variantPath} = require("../lib/moderation/photoVariants.js");
const {
  startFaceAnchorVerification,
  submitFaceAnchorVerification,
} = require("../lib/faceAnchor/faceAnchorService.js");
const {PROCESSING_STALE_MS} = require("../lib/moderation/types.js");
const {
  CONSENT,
  JPEG,
  T0,
  createFaceAnchorWorld,
  publishedPath,
  rejectsWith,
  verdict,
} = require("./helpers/faceAnchorHarness.cjs");

const UID = "member-1";
const FOUR = ["p1", "p2", "p3", "p4"];

const pendingPath = (id, uid = UID) => `users/${uid}/profile/pending/${id}.jpg`;
const thumbPath = (id, uid = UID) => variantPath(uid, id, "thumb");
const cardPath = (id, uid = UID) => variantPath(uid, id, "card");

/**
 * A finished profile whose photos are stored the way the pipeline leaves them:
 * the published original, both variants, and the pending upload it was
 * published from.
 */
function world(options = {}) {
  const w = createFaceAnchorWorld({
    photos: FOUR,
    ...options,
    profile: {profileCompleted: true, ...(options.profile ?? {})},
  });
  for (const id of options.photos ?? FOUR) {
    w.bucket.put(pendingPath(id), JPEG(`pending-${id}`));
    w.bucket.put(thumbPath(id), JPEG(`thumb-${id}`));
    w.bucket.put(cardPath(id), JPEG(`card-${id}`));
  }
  return w;
}

function worldWithAnchors(anchorIds, options = {}) {
  const ledger = {...(options.ledger ?? {})};
  anchorIds.forEach((id, index) => {
    ledger[id] = {...(ledger[id] ?? {}), faceAnchor: verdict(UID, id, {verifiedAtMs: T0 + index * 1000})};
  });
  return world({...options, ledger});
}

function remove(w, photoId, uid = UID) {
  return deleteProfilePhoto({db: w.db, bucket: () => w.bucket, now: () => w.now}, uid, {photoId});
}

const ids = (w) => w.profile().photos.map((photo) => photo.id);
const storedFor = (w, id) => [...w.bucket.files.keys()].filter((path) => path.includes(`/${id}`));

/** Everything about the world a refused request must leave alone. */
function snapshot(w) {
  return JSON.stringify({
    profile: w.profile(),
    ledger: FOUR.map((id) => w.ledger(id)),
    files: [...w.bucket.files.keys()].sort(),
  });
}

describe("deleting a published photo removes everything stored for it", () => {
  it("takes the photo off the profile and closes the gap it left", async () => {
    const w = world();
    const result = await remove(w, "p2");
    assert.deepEqual(result, {photoId: "p2", removed: true, cleanup: "complete"});
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
    assert.deepEqual(w.profile().photos.map((p) => p.order), [0, 1, 2]);
    assert.deepEqual(w.profile().photos.map((p) => p.isPrimary), [true, false, false]);
  });

  it("deletes the published original, both variants and the pending upload", async () => {
    const w = world();
    await remove(w, "p2");
    assert.deepEqual(storedFor(w, "p2"), []);
    // Nothing else in the member's storage is touched.
    for (const id of ["p1", "p3", "p4"]) {
      assert.equal(storedFor(w, id).length, 4, id);
    }
  });

  it("deletes the ledger entry and leaves the others", async () => {
    const w = world();
    await remove(w, "p2");
    assert.equal(w.ledger("p2"), undefined);
    assert.equal(w.ledger("p1").status, "approved");
  });

  it("a published object with another extension goes too", async () => {
    const w = world({ledger: {p2: {storagePath: `users/${UID}/profile/photos/p2.png`}}});
    w.bucket.put(`users/${UID}/profile/photos/p2.png`, JPEG("png"));
    await remove(w, "p2");
    assert.deepEqual(storedFor(w, "p2"), []);
  });

  it("reconciliation afterwards has nothing to put back", async () => {
    const w = world();
    await remove(w, "p2");
    assert.equal(await reconcilePhotoModeration(w.db, UID, w.bucket), false);
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("an id written several times is removed in one go", async () => {
    const w = world();
    const photos = w.profile().photos;
    await w.db.doc(`profiles/${UID}`).set({photos: [...photos, {...photos[1]}]}, {merge: true});
    await remove(w, "p2");
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("removing the primary photo makes the next one primary", async () => {
    const w = world();
    await remove(w, "p1");
    assert.deepEqual(ids(w), ["p2", "p3", "p4"]);
    assert.deepEqual(w.profile().photos.map((p) => p.isPrimary), [true, false, false]);
  });
});

describe("the photo minimum", () => {
  it("a finished profile keeps three photos", async () => {
    const w = world({photos: ["p1", "p2", "p3"]});
    const before = snapshot(w);
    await rejectsWith(remove(w, "p2"), "photo_min_required");
    assert.equal(snapshot(w), before);
    assert.deepEqual(w.bucket.deletes, []);
  });

  it("the same id repeated does not count as more photos", async () => {
    const w = world({photos: ["p1", "p2", "p3"]});
    const photos = w.profile().photos;
    await w.db.doc(`profiles/${UID}`).set({photos: [...photos, {...photos[0]}]}, {merge: true});
    await rejectsWith(remove(w, "p2"), "photo_min_required");
  });

  it("does not apply while the profile is still being set up", async () => {
    const w = world({photos: ["p1", "p2", "p3"], profile: {profileCompleted: false}});
    const result = await remove(w, "p2");
    assert.equal(result.cleanup, "complete");
    assert.deepEqual(ids(w), ["p1", "p3"]);
  });
});

describe("the last Face Anchor cannot be deleted", () => {
  it("refuses the only verified photo and deletes nothing", async () => {
    const w = worldWithAnchors(["p1"]);
    const before = snapshot(w);
    await rejectsWith(remove(w, "p1"), "photo_last_face_anchor");
    assert.equal(snapshot(w), before);
    assert.deepEqual(w.bucket.deletes, []);
  });

  it("refuses it even while a stale write has it missing from the array", async () => {
    // The window the reconciling trigger closes: the array has lost the
    // anchor, the ledger has not. Deleting now would leave nothing to restore.
    const w = worldWithAnchors(["p1"]);
    const photos = w.profile().photos.filter((photo) => photo.id !== "p1");
    await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});
    await rejectsWith(remove(w, "p1"), "photo_last_face_anchor");
    assert.equal(w.bucket.has(publishedPath(UID, "p1")), true);
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    assert.equal(ids(w)[0], "p1");
  });

  it("an anchor that is only held for review does not count as the other one", async () => {
    const w = worldWithAnchors(["p1", "p2"], {ledger: {p2: {status: "manual_review"}}});
    await rejectsWith(remove(w, "p1"), "photo_last_face_anchor");
  });

  it("a verified photo may go when another one stays, which becomes the primary", async () => {
    const w = worldWithAnchors(["p1", "p3"]);
    await reconcilePhotoModeration(w.db, UID, w.bucket);
    const result = await remove(w, "p1");
    assert.equal(result.cleanup, "complete");
    assert.deepEqual(ids(w), ["p3", "p2", "p4"]);
    assert.equal(w.profile().photos[0].isPrimary, true);
    assert.equal(w.profile().photos[0].faceAnchorVerified, true);
    assert.deepEqual(w.profile().faceAnchorPhotoIds, ["p3"]);
    assert.equal(w.ledger("p1"), undefined);
    assert.deepEqual(storedFor(w, "p1"), []);
  });
});

describe("a photo the pipeline is working on", () => {
  const processing = (ageMs) => ({
    status: "processing",
    moderatedAt: Timestamp.fromMillis(T0 - ageMs),
  });

  it("cannot be deleted mid-run: the result would bring it back", async () => {
    const w = world({ledger: {p2: processing(1000)}});
    const before = snapshot(w);
    await rejectsWith(remove(w, "p2"), "photo_processing");
    assert.equal(snapshot(w), before);
  });

  it("can be deleted once that run is stale", async () => {
    const w = world({ledger: {p2: processing(PROCESSING_STALE_MS + 1)}});
    const result = await remove(w, "p2");
    assert.equal(result.cleanup, "complete");
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
  });

  it("an upload deleted before its event is handled does not return", async () => {
    const w = world({photos: ["p1", "p2", "p3"], profile: {profileCompleted: false}});
    // A fourth photo: uploaded and written to the profile, not yet moderated.
    w.bucket.put(pendingPath("fresh"), JPEG("fresh"));
    const photos = [...w.profile().photos, {id: "fresh", order: 3, isPrimary: false, storagePath: pendingPath("fresh")}];
    await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});

    await remove(w, "fresh");
    assert.equal(w.bucket.has(pendingPath("fresh")), false);

    // The Storage event for the upload arrives afterwards.
    w.db.resetStats();
    const status = await processPendingProfilePhoto({
      db: w.db,
      bucket: w.bucket,
      uid: UID,
      imageId: "fresh",
      pendingPath: pendingPath("fresh"),
      contentType: "image/jpeg",
      sizeBytes: 10,
    });
    assert.equal(status, "pending");
    assert.equal(w.db.stats().writes, 0);
    assert.deepEqual(ids(w), ["p1", "p2", "p3"]);
    assert.equal(w.ledger("fresh"), undefined);
  });
});

describe("a moderation result that arrives after the delete", () => {
  // These fixture bytes are approved by the smoke fast path, which exists only
  // in the emulator process — so that is the process these tests run as.
  let savedEmulatorFlag;
  beforeEach(() => {
    savedEmulatorFlag = process.env.FUNCTIONS_EMULATOR;
    process.env.FUNCTIONS_EMULATOR = "true";
  });
  afterEach(() => {
    if (savedEmulatorFlag === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = savedEmulatorFlag;
  });

  /** Runs `action` just before the nth transaction the pipeline opens. */
  function beforeTransaction(w, nth, action) {
    const run = w.db.runTransaction.bind(w.db);
    let seen = 0;
    w.db.runTransaction = async (fn) => {
      seen += 1;
      if (seen === nth) {
        w.db.runTransaction = run;
        await action();
      }
      return run(fn);
    };
  }

  function upload(w, id) {
    const path = pendingPath(id);
    w.bucket.put(path, JPEG(id));
    return {
      db: w.db,
      bucket: w.bucket,
      uid: UID,
      imageId: id,
      pendingPath: path,
      contentType: "image/jpeg",
      sizeBytes: 10,
    };
  }

  it("is dropped: the photo deleted between the decision and its projection stays deleted", async () => {
    const w = world();
    await w.db.doc(`users/${UID}`).set({isSmokeTestUser: true}, {merge: true});
    // The pipeline opens two transactions: one projecting "processing", one
    // projecting the decision. The ledger already says "approved" by the
    // second, so the delete is allowed there.
    let result;
    beforeTransaction(w, 2, async () => {
      result = await remove(w, "fresh");
    });
    const status = await processPendingProfilePhoto(upload(w, "fresh"));
    assert.equal(status, "approved");
    assert.deepEqual(result, {photoId: "fresh", removed: true, cleanup: "complete"});
    assert.deepEqual(ids(w), FOUR);
    assert.equal(w.ledger("fresh"), undefined);
    assert.deepEqual(storedFor(w, "fresh"), []);
    assert.equal(await reconcilePhotoModeration(w.db, UID, w.bucket), false);
  });

  it("while the pipeline is still working the delete is refused instead", async () => {
    const w = world();
    await w.db.doc(`users/${UID}`).set({isSmokeTestUser: true}, {merge: true});
    let refusal;
    beforeTransaction(w, 1, async () => {
      refusal = await remove(w, "fresh").catch((error) => error);
    });
    await processPendingProfilePhoto(upload(w, "fresh"));
    assert.equal(refusal.message, "photo_processing");
    assert.equal(w.ledger("fresh").status, "approved");
    assert.ok(ids(w).includes("fresh"));
  });
});

describe("a delete racing a Face Anchor verification of the same photo", () => {
  it("the verification ends without a verdict and does not recreate the ledger entry", async () => {
    const w = world();
    const {attemptId} = await startFaceAnchorVerification(w.deps, UID, {photoId: "p2", consentVersion: CONSENT});
    w.uploadSelfie(attemptId);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const pending = submitFaceAnchorVerification(w.deps, UID, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));

    const result = await remove(w, "p2");
    release();

    assert.deepEqual(result, {photoId: "p2", removed: true, cleanup: "complete"});
    assert.equal((await pending).status, "error");
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
    assert.equal(w.profile().faceAnchorPhotoIds, undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
  });
});

describe("a photo moderation has ruled on stays on record", () => {
  it("a rejected photo leaves the profile but keeps its ledger entry", async () => {
    const w = world({ledger: {p2: {status: "rejected", reason: "nudity"}}});
    const result = await remove(w, "p2");
    assert.deepEqual(result, {photoId: "p2", removed: true, cleanup: "retained"});
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
    assert.equal(w.ledger("p2").status, "rejected");
    assert.deepEqual(w.bucket.deletes, []);
  });

  it("so the rejected id still cannot be uploaded again", async () => {
    const w = world({ledger: {p2: {status: "rejected"}}});
    await remove(w, "p2");
    w.bucket.put(pendingPath("p2"), JPEG("again"));
    const status = await processPendingProfilePhoto({
      db: w.db,
      bucket: w.bucket,
      uid: UID,
      imageId: "p2",
      pendingPath: pendingPath("p2"),
      contentType: "image/jpeg",
      sizeBytes: 10,
    });
    assert.equal(status, "rejected");
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("a photo held for review keeps its image for the reviewer", async () => {
    const w = world({ledger: {p2: {status: "manual_review", reason: "user-report"}}});
    const result = await remove(w, "p2");
    assert.equal(result.cleanup, "retained");
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
    assert.equal(w.ledger("p2").status, "manual_review");
    assert.equal(w.bucket.has(publishedPath(UID, "p2")), true);
  });
});

describe("a kept record says the member removed the photo", () => {
  const QUEUED_AT = Timestamp.fromMillis(T0 - 60 * 60 * 1000);
  const held = (extra = {}) => ({status: "manual_review", reason: "user-report", updatedAt: QUEUED_AT, ...extra});
  /** Held before it was ever published: only the upload exists. */
  const heldUnpublished = () => held({storagePath: null, downloadUrl: null});
  const uploadEvent = (w, id) => ({
    db: w.db,
    bucket: w.bucket,
    uid: UID,
    imageId: id,
    pendingPath: pendingPath(id),
    contentType: "image/jpeg",
    sizeBytes: 10,
  });

  it("a photo held for review is marked, without losing its place in the review queue", async () => {
    const w = world({ledger: {p2: held()}});
    await remove(w, "p2");
    const entry = w.ledger("p2");
    assert.equal(entry.removedByMemberAt.toMillis(), w.now);
    assert.equal(entry.updatedAt.toMillis(), QUEUED_AT.toMillis());
    assert.equal(entry.status, "manual_review");
  });

  it("a rejected photo is marked too", async () => {
    const w = world({ledger: {p2: {status: "rejected", reason: "nudity"}}});
    await remove(w, "p2");
    assert.equal(w.ledger("p2").removedByMemberAt.toMillis(), w.now);
  });

  it("a deleted photo leaves no record to mark", async () => {
    const w = world();
    await remove(w, "p2");
    assert.equal(w.ledger("p2"), undefined);
  });

  it("the mark is made once: a repeated call does not move it", async () => {
    const w = world({ledger: {p2: held()}});
    await remove(w, "p2");
    const first = w.ledger("p2").removedByMemberAt.toMillis();
    w.advance(60 * 1000);
    w.db.resetStats();
    const again = await remove(w, "p2");
    assert.deepEqual(again, {photoId: "p2", removed: false, cleanup: "retained"});
    assert.equal(w.ledger("p2").removedByMemberAt.toMillis(), first);
    assert.equal(w.db.stats().writes, 0);
  });

  it("a photo an older client took out of the array is marked when the member asks again", async () => {
    const w = world({ledger: {p2: held()}});
    const photos = w.profile().photos.filter((photo) => photo.id !== "p2");
    await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});
    const result = await remove(w, "p2");
    assert.deepEqual(result, {photoId: "p2", removed: false, cleanup: "retained"});
    assert.equal(w.ledger("p2").removedByMemberAt.toMillis(), w.now);
  });

  it("a decision that arrives afterwards is recorded but does not bring the photo back", async () => {
    const w = world({ledger: {p2: held()}});
    await remove(w, "p2");
    const projection = await setPhotoModerationStatus(w.db, UID, "p2", {
      moderationStatus: "approved",
      moderatedBy: "system",
    });
    assert.deepEqual(projection, {onProfile: false});
    assert.equal(w.ledger("p2").status, "approved");
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("an upload event redelivered afterwards does not moderate it again", async () => {
    const w = world({ledger: {p2: heldUnpublished()}});
    await remove(w, "p2");
    w.db.resetStats();
    const status = await processPendingProfilePhoto(uploadEvent(w, "p2"));
    assert.equal(status, "manual_review");
    assert.equal(w.db.stats().writes, 0);
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
    // The upload is the only image the reviewer has.
    assert.equal(w.bucket.has(pendingPath("p2")), true);
  });

  it("without the mark the pipeline still adds a photo the client has not written yet", async () => {
    const w = world();
    w.bucket.put(pendingPath("fresh"), JPEG("fresh"));
    const projection = await setPhotoModerationStatus(w.db, UID, "fresh", {moderationStatus: "processing"});
    assert.deepEqual(projection, {onProfile: true});
    assert.deepEqual(ids(w), [...FOUR, "fresh"]);
  });

  it("a caller that only updates leaves a missing photo out", async () => {
    const w = world();
    const projection = await setPhotoModerationStatus(
      w.db, UID, "fresh", {moderationStatus: "manual_review"}, {whenAbsent: "skip"});
    assert.deepEqual(projection, {onProfile: false});
    assert.deepEqual(ids(w), FOUR);
  });
});

describe("a photo that is not on the profile", () => {
  it("left behind by an older client's array rewrite: the leftovers are cleaned up", async () => {
    const w = world();
    const photos = w.profile().photos.filter((photo) => photo.id !== "p2");
    await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});
    const result = await remove(w, "p2");
    assert.deepEqual(result, {photoId: "p2", removed: false, cleanup: "complete"});
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });

  it("is not held to the photo minimum: the profile does not get smaller", async () => {
    const w = world();
    const photos = w.profile().photos.filter((photo) => photo.id !== "p4");
    await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});
    const result = await remove(w, "p4");
    assert.equal(result.cleanup, "complete");
    assert.deepEqual(ids(w), ["p1", "p2", "p3"]);
  });

  it("an unknown id is a no-op that writes nothing", async () => {
    const w = world();
    w.db.resetStats();
    const result = await remove(w, "never-existed");
    assert.deepEqual(result, {photoId: "never-existed", removed: false, cleanup: "complete"});
    assert.equal(w.db.stats().writes, 0);
    assert.deepEqual(ids(w), FOUR);
  });

  it("a repeated call is harmless", async () => {
    const w = world();
    await remove(w, "p2");
    const again = await remove(w, "p2");
    assert.deepEqual(again, {photoId: "p2", removed: false, cleanup: "complete"});
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
  });
});

describe("when Storage will not delete an object", () => {
  function failingOn(w, path) {
    const file = w.bucket.file.bind(w.bucket);
    let failing = true;
    w.bucket.file = (name) => {
      const handle = file(name);
      if (name !== path) {
        return handle;
      }
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

  it("the photo is off the profile and the caller is told the cleanup is incomplete", async () => {
    const w = world();
    failingOn(w, publishedPath(UID, "p2"));
    const result = await remove(w, "p2");
    assert.deepEqual(result, {photoId: "p2", removed: true, cleanup: "incomplete"});
    assert.deepEqual(ids(w), ["p1", "p3", "p4"]);
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), [publishedPath(UID, "p2")]);
  });

  it("a repeat call finishes the job", async () => {
    const w = world();
    const recover = failingOn(w, publishedPath(UID, "p2"));
    await remove(w, "p2");
    recover();
    const result = await remove(w, "p2");
    assert.deepEqual(result, {photoId: "p2", removed: false, cleanup: "complete"});
    assert.equal(w.ledger("p2"), undefined);
    assert.deepEqual(storedFor(w, "p2"), []);
  });
});

describe("what a request may name", () => {
  it("rejects anything that is not a plain photo id", async () => {
    const w = world();
    const before = snapshot(w);
    for (const photoId of [undefined, null, "", "   ", 7, {}, "a/b", "../p1", "p1.jpg", "x".repeat(129)]) {
      const error = await rejectsWith(remove(w, photoId), "photo-id-required");
      assert.equal(error.code, "invalid-argument");
    }
    assert.equal(snapshot(w), before);
    assert.deepEqual(w.bucket.deletes, []);
  });

  it("only ever reaches the caller's own photos", async () => {
    const w = world();
    const before = snapshot(w);
    const result = await remove(w, "p2", "someone-else");
    assert.equal(result.removed, false);
    assert.equal(snapshot(w), before);
    assert.ok(w.bucket.deletes.every((path) => path.startsWith("users/someone-else/profile/")));
  });

  it("never names the quarantine or anything outside the member's profile folder", () => {
    const paths = photoObjectPaths(UID, "p2", `moderation-quarantine/${UID}/p2.jpg`);
    assert.ok(paths.every((path) => path.startsWith(`users/${UID}/profile/`)));
    assert.ok(paths.includes(publishedPath(UID, "p2")));
    assert.ok(paths.includes(thumbPath("p2")));
    assert.ok(paths.includes(cardPath("p2")));
    assert.ok(paths.includes(pendingPath("p2")));
  });
});

describe("photosWithout", () => {
  it("keeps the member's order and their choice of primary", () => {
    const next = photosWithout([
      {id: "a", order: 2, isPrimary: false},
      {id: "b", order: 0, isPrimary: false},
      {id: "c", order: 1, isPrimary: true},
      {id: "d", order: 3, isPrimary: false},
    ], "b");
    assert.deepEqual(next.map((p) => [p.id, p.order, p.isPrimary]), [
      ["c", 0, true],
      ["a", 1, false],
      ["d", 2, false],
    ]);
  });

  it("orders photos that carry no order by their position", () => {
    const next = photosWithout([{id: "a"}, {id: "b"}, {id: "c"}], "a");
    assert.deepEqual(next.map((p) => [p.id, p.order, p.isPrimary]), [["b", 0, true], ["c", 1, false]]);
  });
});
