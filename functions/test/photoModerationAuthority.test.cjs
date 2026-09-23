const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  reconcilePhotoModeration,
} = require("../lib/moderation/photoModerationService.js");
const {
  isPublishedStoragePath,
  reconcilePhoto,
} = require("../lib/moderation/photoModerationLedger.js");
const {
  approvedPhotos,
  countUsableDiscoveryPhotos,
} = require("../lib/profileSafety.js");

const UID = "user-a";

/**
 * Minimal Firestore stand-in: just the surface reconcilePhotoModeration uses.
 * `writes` records every document write so a test can assert what the server
 * pushed back onto the profile.
 */
function fakeDb({ledger = {}} = {}) {
  const writes = [];
  const ledgerDocs = Object.entries(ledger).map(([id, data]) => ({id, data: () => data}));
  return {
    writes,
    collection(path) {
      assert.equal(path, `users/${UID}/photoModeration`);
      return {async get() {
        return {docs: ledgerDocs};
      }};
    },
    doc(path) {
      return {
        async set(data, options) {
          writes.push({path, data, options});
        },
        async get() {
          return {exists: false, data: () => undefined};
        },
      };
    },
  };
}

function fakeBucket(existingPaths = []) {
  return {
    file(path) {
      return {async exists() {
        return [existingPaths.includes(path)];
      }};
    },
  };
}

function photosAfter(db) {
  const write = db.writes.filter((w) => w.path === `profiles/${UID}`).pop();
  return write ? write.data.photos : null;
}

describe("photo moderation authority — client cannot self-approve", () => {
  it("reverts a client-written approval with no ledger entry", async () => {
    const db = fakeDb();
    const changed = await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", downloadUrl: "https://attacker.example/x.jpg"},
    ]);
    assert.equal(changed, true);
    assert.equal(photosAfter(db)[0].moderationStatus, "pending");
  });

  it("moderatedBy:'system' no longer establishes authority", async () => {
    const db = fakeDb();
    const changed = await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", moderatedBy: "system"},
    ]);
    assert.equal(changed, true);
    const photo = photosAfter(db)[0];
    assert.equal(photo.moderationStatus, "pending");
    assert.equal(photo.moderatedBy, null);
  });

  it("moderatedBy:'report-pipeline' no longer establishes authority", async () => {
    const db = fakeDb();
    const changed = await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", moderatedBy: "report-pipeline"},
    ]);
    assert.equal(changed, true);
    assert.equal(photosAfter(db)[0].moderationStatus, "pending");
  });

  it("an entirely new approved photo id is forced back to pending", async () => {
    const db = fakeDb({ledger: {p1: {status: "approved", storagePath: `users/${UID}/profile/photos/p1.jpg`}}});
    const changed = await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved"},
      {id: "smuggled", moderationStatus: "approved", moderatedBy: "system"},
    ]);
    assert.equal(changed, true);
    const photos = photosAfter(db);
    assert.equal(photos.find((p) => p.id === "p1").moderationStatus, "approved");
    assert.equal(photos.find((p) => p.id === "smuggled").moderationStatus, "pending");
  });

  it("an arbitrary external downloadUrl cannot ride on an approved entry", async () => {
    const trusted = "https://firebasestorage.googleapis.com/v0/b/x/o/real.jpg";
    const db = fakeDb({
      ledger: {p1: {status: "approved", storagePath: `users/${UID}/profile/photos/p1.jpg`, downloadUrl: trusted}},
    });
    await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", downloadUrl: "https://attacker.example/x.jpg"},
    ]);
    const photo = photosAfter(db)[0];
    assert.equal(photo.downloadUrl, trusted);
    assert.equal(photo.storagePath, `users/${UID}/profile/photos/p1.jpg`);
  });

  it("a client cannot downgrade a rejection to hide it", async () => {
    const db = fakeDb({ledger: {p1: {status: "rejected", reason: "nudity"}}});
    const changed = await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", moderatedBy: "system"},
    ]);
    assert.equal(changed, true);
    const photo = photosAfter(db)[0];
    assert.equal(photo.moderationStatus, "rejected");
    assert.equal(photo.moderationReason, "nudity");
  });

  it("a client cannot escape manual review", async () => {
    const db = fakeDb({ledger: {p1: {status: "manual_review", moderatedBy: "report-pipeline"}}});
    await reconcilePhotoModeration(db, UID, [{id: "p1", moderationStatus: "approved"}]);
    assert.equal(photosAfter(db)[0].moderationStatus, "manual_review");
  });
});

describe("photo moderation authority — legitimate flows keep working", () => {
  it("a server-approved photo survives reconciliation untouched", async () => {
    const storagePath = `users/${UID}/profile/photos/p1.jpg`;
    const db = fakeDb({ledger: {p1: {status: "approved", storagePath, downloadUrl: "https://cdn/p1.jpg", moderatedBy: "system"}}});
    const changed = await reconcilePhotoModeration(db, UID, [
      {
        id: "p1",
        moderationStatus: "approved",
        moderationReason: null,
        moderatedBy: "system",
        storagePath,
        downloadUrl: "https://cdn/p1.jpg",
        order: 0,
        isPrimary: true,
      },
    ]);
    // Nothing to correct -> no write -> the trigger does not loop.
    assert.equal(changed, false);
    assert.equal(db.writes.length, 0);
  });

  it("a fresh pending upload is left as pending without a write", async () => {
    const db = fakeDb();
    const changed = await reconcilePhotoModeration(db, UID, [
      {
        id: "p1",
        moderationStatus: "pending",
        moderationReason: null,
        moderatedAt: null,
        moderatedBy: null,
        order: 0,
        isPrimary: true,
      },
    ]);
    assert.equal(changed, false);
  });

  it("client-owned presentation fields are preserved", async () => {
    const db = fakeDb({ledger: {p1: {status: "approved", storagePath: `users/${UID}/profile/photos/p1.jpg`}}});
    await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "pending", order: 3, isPrimary: true, thumbUrl: "https://cdn/t.jpg"},
    ]);
    const photo = photosAfter(db)[0];
    assert.equal(photo.order, 3);
    assert.equal(photo.isPrimary, true);
    assert.equal(photo.moderationStatus, "approved");
    // B-11: thumbUrl moved from client-owned to server-owned. Discovery renders
    // `thumbUrl ?? downloadUrl`, so a client value here would have been
    // preferred over the moderated URL. Ordering and identity stay client-owned.
    assert.equal(photo.thumbUrl, null);
  });

  it("reconciliation is idempotent", async () => {
    const db = fakeDb({ledger: {p1: {status: "approved", storagePath: `users/${UID}/profile/photos/p1.jpg`}}});
    await reconcilePhotoModeration(db, UID, [{id: "p1", moderationStatus: "pending"}]);
    const firstPass = photosAfter(db);
    const db2 = fakeDb({ledger: {p1: {status: "approved", storagePath: `users/${UID}/profile/photos/p1.jpg`}}});
    const changedAgain = await reconcilePhotoModeration(db2, UID, firstPass);
    assert.equal(changedAgain, false);
  });

  it("an empty photo array is a no-op", async () => {
    const db = fakeDb();
    assert.equal(await reconcilePhotoModeration(db, UID, []), false);
  });
});

describe("legacy photos published by the pipeline", () => {
  it("are grandfathered when the storage object really exists", async () => {
    const storagePath = `users/${UID}/profile/photos/legacy.jpg`;
    const db = fakeDb();
    await reconcilePhotoModeration(
      db,
      UID,
      [{id: "legacy", moderationStatus: "approved", storagePath, downloadUrl: "https://cdn/legacy.jpg"}],
      fakeBucket([storagePath]),
    );
    const ledgerWrite = db.writes.find((w) => w.path === `users/${UID}/photoModeration/legacy`);
    assert.ok(ledgerWrite, "expected a ledger backfill write");
    assert.equal(ledgerWrite.data.status, "approved");
    assert.equal(ledgerWrite.data.moderatedBy, "legacy-backfill");
  });

  it("are not grandfathered when the claimed object does not exist", async () => {
    const db = fakeDb();
    await reconcilePhotoModeration(
      db,
      UID,
      [{id: "fake", moderationStatus: "approved", storagePath: `users/${UID}/profile/photos/fake.jpg`}],
      fakeBucket([]),
    );
    assert.equal(photosAfter(db)[0].moderationStatus, "pending");
  });

  it("a claimed path outside the server-only prefix is never grandfathered", async () => {
    const pendingPath = `users/${UID}/profile/pending/x.jpg`;
    assert.equal(isPublishedStoragePath(UID, pendingPath), false);
    assert.equal(isPublishedStoragePath(UID, "https://attacker.example/x.jpg"), false);
    assert.equal(isPublishedStoragePath(UID, `users/other/profile/photos/x.jpg`), false);
    assert.equal(isPublishedStoragePath(UID, `users/${UID}/profile/photos/x.jpg`), true);

    const db = fakeDb();
    await reconcilePhotoModeration(
      db,
      UID,
      [{id: "x", moderationStatus: "approved", storagePath: pendingPath}],
      fakeBucket([pendingPath]),
    );
    assert.equal(photosAfter(db)[0].moderationStatus, "pending");
  });
});

describe("discovery eligibility fails closed", () => {
  it("a photo with no moderationStatus is not approved", () => {
    assert.equal(approvedPhotos([{id: "p1"}]).length, 0);
    assert.equal(countUsableDiscoveryPhotos([{id: "p1"}, {id: "p2"}]), 0);
  });

  it("only explicitly approved photos count toward discovery", () => {
    const photos = [
      {id: "a", moderationStatus: "approved"},
      {id: "b", moderationStatus: "pending"},
      {id: "c", moderationStatus: "rejected"},
      {id: "d", moderationStatus: "manual_review"},
      {id: "e"},
    ];
    assert.equal(countUsableDiscoveryPhotos(photos), 1);
  });
});

describe("reconcilePhoto projection", () => {
  it("clears moderation metadata when there is no ledger entry", () => {
    const out = reconcilePhoto(
      {id: "p1", moderationStatus: "approved", moderatedBy: "system", moderationReason: "ok"},
      null,
    );
    assert.deepEqual(
      {
        moderationStatus: out.moderationStatus,
        moderatedBy: out.moderatedBy,
        moderationReason: out.moderationReason,
        moderatedAt: out.moderatedAt,
      },
      {moderationStatus: "pending", moderatedBy: null, moderationReason: null, moderatedAt: null},
    );
  });

  it("does not move storagePath or downloadUrl for a non-approved ledger entry", () => {
    const out = reconcilePhoto(
      {id: "p1", storagePath: "client/path.jpg", downloadUrl: "https://client/x.jpg"},
      {status: "rejected", storagePath: "server/path.jpg", downloadUrl: "https://server/x.jpg"},
    );
    assert.equal(out.moderationStatus, "rejected");
    assert.equal(out.storagePath, "client/path.jpg");
  });
});

describe("B-11 — thumbnail URL authority", () => {
  it("a client-supplied thumbUrl is stripped when there is no ledger entry", async () => {
    const db = fakeDb();
    const changed = await reconcilePhotoModeration(db, UID, [
      {id: "p1", thumbUrl: "https://attacker.example/unmoderated.jpg"},
    ]);
    assert.equal(changed, true);
    assert.equal(photosAfter(db)[0].thumbUrl, null);
  });

  it("a client-supplied thumbUrl cannot ride on an approved photo", async () => {
    const storagePath = `users/${UID}/profile/photos/p1.jpg`;
    const trusted = "https://firebasestorage.googleapis.com/v0/b/x/o/real.jpg";
    const db = fakeDb({ledger: {p1: {status: "approved", storagePath, downloadUrl: trusted}}});
    await reconcilePhotoModeration(db, UID, [
      {
        id: "p1",
        moderationStatus: "approved",
        downloadUrl: trusted,
        thumbUrl: "https://attacker.example/unmoderated.jpg",
      },
    ]);
    const photo = photosAfter(db)[0];
    // Discovery renders `thumbUrl ?? downloadUrl`, so a null thumb falls back
    // to the moderated URL rather than the attacker's.
    assert.equal(photo.thumbUrl, null);
    assert.equal(photo.downloadUrl, trusted);
  });

  it("a server-supplied thumbUrl from the ledger is preserved", async () => {
    const storagePath = `users/${UID}/profile/photos/p1.jpg`;
    const serverThumb = "https://firebasestorage.googleapis.com/v0/b/x/o/thumb.jpg";
    const db = fakeDb({
      ledger: {p1: {status: "approved", storagePath, downloadUrl: "https://cdn/p1.jpg", thumbUrl: serverThumb}},
    });
    await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", thumbUrl: "https://attacker.example/x.jpg"},
    ]);
    assert.equal(photosAfter(db)[0].thumbUrl, serverThumb);
  });

  it("a pending photo gets no thumbnail at all", async () => {
    const db = fakeDb({ledger: {p1: {status: "pending"}}});
    await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "pending", thumbUrl: "https://attacker.example/x.jpg"},
    ]);
    const photo = photosAfter(db)[0];
    assert.equal(photo.thumbUrl, null);
    assert.equal(photo.moderationStatus, "pending");
  });

  it("a rejected photo keeps no trusted thumbnail", async () => {
    const db = fakeDb({ledger: {p1: {status: "rejected", reason: "nudity"}}});
    await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "approved", thumbUrl: "https://attacker.example/x.jpg"},
    ]);
    const photo = photosAfter(db)[0];
    assert.equal(photo.thumbUrl, null);
    assert.equal(photo.moderationStatus, "rejected");
  });

  it("reconciliation stays idempotent with thumbUrl owned by the server", async () => {
    const storagePath = `users/${UID}/profile/photos/p1.jpg`;
    const ledger = {p1: {status: "approved", storagePath, downloadUrl: "https://cdn/p1.jpg"}};
    const db = fakeDb({ledger});
    await reconcilePhotoModeration(db, UID, [
      {id: "p1", moderationStatus: "pending", thumbUrl: "https://attacker.example/x.jpg"},
    ]);
    const first = photosAfter(db);
    const db2 = fakeDb({ledger});
    assert.equal(await reconcilePhotoModeration(db2, UID, first), false);
  });
});
