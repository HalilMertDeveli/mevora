const {afterEach, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {FieldValue} = require("firebase-admin/firestore");
const {
  computePhotoInvariants,
  dedupePhotos,
} = require("../lib/moderation/photoInvariants.js");
const {
  isLedgerFaceAnchor,
  ledgerEntryFromData,
  reconcilePhoto,
  writeLedgerEntry,
} = require("../lib/moderation/photoModerationLedger.js");
const {
  processPendingProfilePhoto,
  reconcilePhotoModeration,
  setPhotoModerationStatus,
} = require("../lib/moderation/photoModerationService.js");
const {
  JPEG,
  T0,
  createFaceAnchorWorld,
  publishedPath,
  verdict,
} = require("./helpers/faceAnchorHarness.cjs");

const UID = "member-1";

/** A world where the listed photo ids already carry a verdict. */
function worldWithAnchors(anchorIds, options = {}) {
  const ledger = {...(options.ledger ?? {})};
  anchorIds.forEach((id, index) => {
    ledger[id] = {...(ledger[id] ?? {}), faceAnchor: verdict(UID, id, {verifiedAtMs: T0 + index * 1000})};
  });
  return createFaceAnchorWorld({...options, ledger});
}

/** What a client does: replace the whole photos array. */
async function clientWrites(w, photos) {
  await w.db.doc(`profiles/${UID}`).set({photos}, {merge: true});
}

async function reconcile(w) {
  return reconcilePhotoModeration(w.db, UID, w.bucket);
}

function ledgerMap(entries) {
  return new Map(Object.entries(entries).map(([id, data]) => [id, ledgerEntryFromData(data)]));
}

const approved = (id, extra = {}) => ({
  status: "approved",
  storagePath: publishedPath(UID, id),
  ...extra,
});

describe("face anchor projection — the client cannot forge it", () => {
  it("a client-written faceAnchorVerified is removed", async () => {
    const w = createFaceAnchorWorld();
    const photos = w.profile().photos.map((p) => ({...p, faceAnchorVerified: true}));
    await clientWrites(w, photos);
    assert.equal(await reconcile(w), true);
    for (const photo of w.profile().photos) {
      assert.equal("faceAnchorVerified" in photo, false);
    }
    assert.equal(w.profile().faceAnchorPhotoIds, undefined);
    assert.equal(w.profile().faceAnchorRequired, undefined);
  });

  it("a forged flag does not make a non-anchor the primary", async () => {
    const w = worldWithAnchors(["p1"]);
    await reconcile(w);
    await clientWrites(w, [
      {id: "p2", order: 0, isPrimary: true, faceAnchorVerified: true, moderationStatus: "approved"},
      {id: "p1", order: 1, isPrimary: false},
      {id: "p3", order: 2, isPrimary: false},
    ]);
    await reconcile(w);
    const photos = w.profile().photos;
    assert.equal(photos[0].id, "p1");
    assert.equal(photos[0].isPrimary, true);
    assert.equal("faceAnchorVerified" in photos.find((p) => p.id === "p2"), false);
  });

  it("the verdict is projected only while the photo is approved", () => {
    const entry = ledgerEntryFromData(approved("p1", {faceAnchor: verdict(UID, "p1")}));
    assert.equal(reconcilePhoto({id: "p1"}, entry).faceAnchorVerified, true);
    const held = ledgerEntryFromData({...approved("p1", {faceAnchor: verdict(UID, "p1")}), status: "manual_review"});
    assert.equal("faceAnchorVerified" in reconcilePhoto({id: "p1", faceAnchorVerified: true}, held), false);
    assert.equal("faceAnchorVerified" in reconcilePhoto({id: "p1", faceAnchorVerified: true}, null), false);
  });

  it("only the exact verdict word counts", () => {
    for (const status of ["Verified", "approved", true, 1, "pending"]) {
      const entry = ledgerEntryFromData(approved("p1", {faceAnchor: {status, storagePath: publishedPath(UID, "p1")}}));
      assert.equal(isLedgerFaceAnchor(entry), false, String(status));
    }
  });

  it("a verdict about a different published object is not an anchor", () => {
    const entry = ledgerEntryFromData(approved("p1", {
      faceAnchor: verdict(UID, "p1", {storagePath: `users/${UID}/profile/photos/p1.png`}),
    }));
    assert.equal(isLedgerFaceAnchor(entry), false);
  });

  it("documents written before Face Anchor reconcile to themselves", async () => {
    const w = createFaceAnchorWorld();
    await reconcile(w);
    const before = JSON.stringify(w.profile());
    assert.equal(await reconcile(w), false);
    assert.equal(JSON.stringify(w.profile()), before);
    assert.equal("faceAnchorPhotoIds" in w.profile(), false);
  });
});

describe("photo invariants — one id, one photo", () => {
  it("repeating an approved id does not multiply approved photos", async () => {
    const w = createFaceAnchorWorld({photos: ["p1"]});
    await clientWrites(w, [{id: "p1"}, {id: "p1"}, {id: "p1"}]);
    await reconcile(w);
    assert.deepEqual(w.profile().photos.map((p) => p.id), ["p1"]);
  });

  it("entries without an id are not collapsed into each other", () => {
    assert.equal(dedupePhotos([{}, {}, {id: "a"}, {id: "a"}]).length, 3);
  });
});

describe("photo invariants — the last anchor cannot be removed", () => {
  it("removing the only anchor puts it back, as the primary photo", async () => {
    const w = worldWithAnchors(["p1"]);
    await reconcile(w);
    await clientWrites(w, w.profile().photos.filter((p) => p.id !== "p1"));
    assert.equal(await reconcile(w), true);
    const profile = w.profile();
    assert.deepEqual(profile.photos.map((p) => p.id), ["p1", "p2", "p3"]);
    assert.equal(profile.photos[0].isPrimary, true);
    assert.equal(profile.photos[0].faceAnchorVerified, true);
    assert.equal(profile.photos[0].downloadUrl, "https://cdn.test/p1.jpg");
    assert.deepEqual(profile.faceAnchorPhotoIds, ["p1"]);
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
  });

  it("emptying the array does not get around it", async () => {
    const w = worldWithAnchors(["p1"]);
    await reconcile(w);
    await clientWrites(w, []);
    await reconcile(w);
    assert.deepEqual(w.profile().photos.map((p) => p.id), ["p1"]);
  });

  it("with two anchors, either may be removed", async () => {
    const w = worldWithAnchors(["p1", "p2"]);
    await reconcile(w);
    await clientWrites(w, w.profile().photos.filter((p) => p.id !== "p1"));
    await reconcile(w);
    const profile = w.profile();
    assert.deepEqual(profile.photos.map((p) => p.id), ["p2", "p3"]);
    assert.equal(profile.photos[0].isPrimary, true);
    assert.deepEqual(profile.faceAnchorPhotoIds, ["p2"]);
  });

  it("removing both of two anchors restores the most recently verified one", async () => {
    const w = worldWithAnchors(["p1", "p2"]);
    await reconcile(w);
    await clientWrites(w, w.profile().photos.filter((p) => p.id === "p3"));
    await reconcile(w);
    assert.deepEqual(w.profile().photos.map((p) => p.id), ["p2", "p3"]);
  });
});

describe("photo invariants — a removed anchor does not stay verified", () => {
  it("the verdict is dropped when the photo leaves and another anchor remains", async () => {
    const w = worldWithAnchors(["p1", "p2"]);
    await reconcile(w);
    await clientWrites(w, w.profile().photos.filter((p) => p.id !== "p1"));
    await reconcile(w);
    assert.equal(w.ledger("p1").faceAnchor, undefined);
    // Putting the id back yields an ordinary approved photo, not an anchor.
    await clientWrites(w, [...w.profile().photos, {id: "p1", order: 9}]);
    await reconcile(w);
    const readded = w.profile().photos.find((p) => p.id === "p1");
    assert.equal(readded.moderationStatus, "approved");
    assert.equal("faceAnchorVerified" in readded, false);
    assert.deepEqual(w.profile().faceAnchorPhotoIds, ["p2"]);
  });
});

describe("photo invariants — the primary photo is a verified anchor", () => {
  it("an unverified photo marked primary does not become primary", async () => {
    const w = worldWithAnchors(["p2"]);
    await reconcile(w);
    await clientWrites(w, [
      {id: "p1", order: 0, isPrimary: true},
      {id: "p2", order: 1, isPrimary: false},
      {id: "p3", order: 2, isPrimary: false},
    ]);
    await reconcile(w);
    const photos = w.profile().photos;
    assert.deepEqual(photos.map((p) => p.id), ["p2", "p1", "p3"]);
    assert.deepEqual(photos.map((p) => p.isPrimary), [true, false, false]);
    assert.deepEqual(photos.map((p) => p.order), [0, 1, 2]);
  });

  it("position, order and the flag are made to agree", async () => {
    const w = worldWithAnchors(["p2"]);
    // The anchor is first in the array and flagged, but a non-anchor has the
    // lowest order: readers that sort by order would show the non-anchor.
    await clientWrites(w, [
      {id: "p2", order: 5, isPrimary: true},
      {id: "p1", order: 0, isPrimary: false},
      {id: "p3", order: 1, isPrimary: false},
    ]);
    await reconcile(w);
    const photos = w.profile().photos;
    assert.equal(photos[0].id, "p2");
    assert.equal(photos[0].order, 0);
    assert.deepEqual(photos.map((p) => p.order), [0, 1, 2]);
  });

  it("two photos flagged primary leave exactly one", async () => {
    const w = worldWithAnchors(["p1", "p2"]);
    await clientWrites(w, [
      {id: "p1", order: 0, isPrimary: true},
      {id: "p2", order: 1, isPrimary: true},
      {id: "p3", order: 2, isPrimary: true},
    ]);
    await reconcile(w);
    assert.deepEqual(w.profile().photos.map((p) => p.isPrimary), [true, false, false]);
  });

  it("the member chooses which of their anchors is primary", async () => {
    const w = worldWithAnchors(["p1", "p3"]);
    await reconcile(w);
    await clientWrites(w, [
      {id: "p1", order: 0, isPrimary: false},
      {id: "p2", order: 1, isPrimary: false},
      {id: "p3", order: 2, isPrimary: true},
    ]);
    await reconcile(w);
    assert.deepEqual(w.profile().photos.map((p) => p.id), ["p3", "p1", "p2"]);
  });

  it("a profile with no anchor keeps the member's own ordering", () => {
    const photos = [
      {id: "p1", order: 2, isPrimary: false},
      {id: "p2", order: 0, isPrimary: true},
    ];
    const result = computePhotoInvariants(photos, ledgerMap({p1: approved("p1"), p2: approved("p2")}));
    assert.deepEqual(result.photos.map((p) => [p.id, p.order, p.isPrimary]), [["p1", 2, false], ["p2", 0, true]]);
    assert.deepEqual(result.faceAnchorPhotoIds, []);
  });
});

describe("photo invariants — moderation overrides the verdict", () => {
  it("a rejected anchor loses its verdict for good", async () => {
    const w = worldWithAnchors(["p1", "p2"]);
    await reconcile(w);
    await setPhotoModerationStatus(w.db, UID, "p1", {moderationStatus: "rejected", moderationReason: "nudity"});
    await reconcile(w);
    assert.equal(w.ledger("p1").faceAnchor, undefined);
    const profile = w.profile();
    assert.deepEqual(profile.faceAnchorPhotoIds, ["p2"]);
    assert.equal(profile.photos[0].id, "p2");
    assert.equal("faceAnchorVerified" in profile.photos.find((p) => p.id === "p1"), false);
    // Re-approval does not bring the verdict back.
    await setPhotoModerationStatus(w.db, UID, "p1", {moderationStatus: "approved"});
    await reconcile(w);
    assert.equal("faceAnchorVerified" in w.profile().photos.find((p) => p.id === "p1"), false);
  });

  it("rejecting the only anchor leaves the profile with none", async () => {
    const w = worldWithAnchors(["p1"]);
    await reconcile(w);
    await setPhotoModerationStatus(w.db, UID, "p1", {moderationStatus: "rejected"});
    await reconcile(w);
    assert.deepEqual(w.profile().faceAnchorPhotoIds, []);
  });

  it("an anchor held for review is not usable, and comes back when cleared", async () => {
    const w = worldWithAnchors(["p1"]);
    await reconcile(w);
    await writeLedgerEntry(w.db, UID, "p1", {status: "manual_review", reason: "user-report"});
    await reconcile(w);
    assert.deepEqual(w.profile().faceAnchorPhotoIds, []);
    assert.equal("faceAnchorVerified" in w.profile().photos.find((p) => p.id === "p1"), false);
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
    await writeLedgerEntry(w.db, UID, "p1", {status: "approved"});
    await reconcile(w);
    assert.deepEqual(w.profile().faceAnchorPhotoIds, ["p1"]);
  });
});

describe("photo invariants — no trigger loop", () => {
  it("a second pass over a reconciled profile writes nothing", async () => {
    const w = worldWithAnchors(["p2"]);
    assert.equal(await reconcile(w), true);
    w.db.resetStats();
    assert.equal(await reconcile(w), false);
    assert.equal(w.db.stats().writes, 0);
  });

  it("a missing profile is never created", async () => {
    const w = worldWithAnchors(["p1"]);
    await w.db.doc(`profiles/${UID}`).delete();
    assert.equal(await reconcile(w), false);
    assert.equal(w.db.has(`profiles/${UID}`), false);
  });
});

describe("a moderated photo id cannot be re-uploaded", () => {
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

  function pending(w, imageId, bytes) {
    const path = `users/${UID}/profile/pending/${imageId}.jpg`;
    w.bucket.put(path, bytes);
    return {
      db: w.db,
      bucket: w.bucket,
      uid: UID,
      imageId,
      pendingPath: path,
      contentType: "image/jpeg",
      sizeBytes: bytes.length,
    };
  }

  it("new bytes under a verified anchor's id are dropped, not published", async () => {
    const w = worldWithAnchors(["p1"]);
    const original = (await w.bucket.file(publishedPath(UID, "p1")).download())[0];
    const options = pending(w, "p1", JPEG("a-different-person"));
    const status = await processPendingProfilePhoto(options);
    assert.equal(status, "approved");
    assert.equal(w.bucket.has(options.pendingPath), false, "the re-uploaded bytes are deleted");
    assert.deepEqual((await w.bucket.file(publishedPath(UID, "p1")).download())[0], original);
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
    assert.equal(w.ledger("p1").status, "approved");
  });

  it("a moderator's removal is not undone by uploading the id again", async () => {
    const w = createFaceAnchorWorld({ledger: {p1: {status: "rejected"}}});
    const options = pending(w, "p1", JPEG("again"));
    assert.equal(await processPendingProfilePhoto(options), "rejected");
    assert.equal(w.ledger("p1").status, "rejected");
    assert.equal(w.bucket.has(options.pendingPath), false);
  });

  it("a photo published but never marked approved is still processed", async () => {
    // The crash-between-publish-and-status case: the object exists under
    // photos/, the ledger still says processing. The retry must not be refused.
    const w = createFaceAnchorWorld({ledger: {p1: {status: "processing"}}});
    await w.db.doc(`users/${UID}`).set({isSmokeTestUser: true}, {merge: true});
    const options = pending(w, "p1", JPEG("first-upload"));
    const status = await processPendingProfilePhoto(options);
    assert.equal(status, "approved");
  });

  it("a first upload is processed as before", async () => {
    const w = createFaceAnchorWorld();
    await w.db.doc(`users/${UID}`).set({isSmokeTestUser: true}, {merge: true});
    const status = await processPendingProfilePhoto(pending(w, "brand-new", JPEG("new")));
    assert.equal(status, "approved");
    assert.equal(w.ledger("brand-new").status, "approved");
  });
});

describe("writeLedgerEntry", () => {
  it("a status-only update keeps the verdict", async () => {
    const w = worldWithAnchors(["p1"]);
    await writeLedgerEntry(w.db, UID, "p1", {status: "manual_review", reason: "user-report"});
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
  });

  it("writes no FieldValue it should not", async () => {
    const w = worldWithAnchors(["p1"]);
    await writeLedgerEntry(w.db, UID, "p1", {status: "approved"});
    assert.notEqual(w.ledger("p1").faceAnchor, FieldValue.delete());
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
  });
});
