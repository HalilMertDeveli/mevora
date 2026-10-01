const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");
const {verdict} = require("./helpers/faceAnchorHarness.cjs");

// deleteAccount.js binds getFirestore()/getAuth() at load; getStorage() is
// resolved per call, so a bucket that actually holds objects replaces the
// no-op one the shared stubs install.
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});
const objects = new Set();
const bucket = {
  async deleteFiles({prefix}) {
    for (const name of [...objects]) {
      if (name.startsWith(prefix)) objects.delete(name);
    }
  },
  async getFiles({prefix}) {
    return [[...objects].filter((name) => name.startsWith(prefix)).map((name) => ({name}))];
  },
};
require("firebase-admin/storage").getStorage = () => ({bucket: () => bucket});

const {deleteUserAccount} = require("../lib/deleteAccount.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");

const UID = "uid-anchor";
const OTHER = "uid-other";
const SELFIE = `face-anchor/pending/${UID}/attempt-1`;
const OTHER_SELFIE = `face-anchor/pending/${OTHER}/attempt-9`;

/**
 * Face Anchor leaves three things behind a member: the verdict on a photo's
 * ledger entry, the attempt state, and — if they uploaded a selfie and never
 * submitted it — the selfie. Deletion has to take all three, and the
 * post-deletion verification has to notice any that survive.
 */
describe("account deletion erases Face Anchor data", () => {
  beforeEach(() => {
    db.reset({
      [`users/${UID}`]: {uid: UID},
      [`profiles/${UID}`]: {uid: UID, faceAnchorRequired: true, faceAnchorPhotoIds: ["p1"]},
      [`users/${UID}/photoModeration/p1`]: {status: "approved", faceAnchor: verdict(UID, "p1")},
      [`users/${UID}/faceAnchor/state`]: {attemptId: "attempt-1", status: "awaiting_selfie", photoId: "p2"},
      [`users/${UID}/rateLimits/faceAnchorStart`]: {windowStart: 1, count: 3},
      [`users/${OTHER}`]: {uid: OTHER},
      [`users/${OTHER}/faceAnchor/state`]: {attemptId: "attempt-9", status: "awaiting_selfie"},
    });
    auth.users.clear();
    auth.addUser(UID);
    auth.addUser(OTHER);
    objects.clear();
    objects.add(SELFIE);
    objects.add(OTHER_SELFIE);
    objects.add(`users/${UID}/profile/photos/p1.jpg`);
  });

  it("removes the verdict, the attempt state and a pending selfie", async () => {
    const result = await callAs(deleteUserAccount, UID);
    assert.equal(result.ok, true);
    assert.equal(db.has(`users/${UID}/faceAnchor/state`), false);
    assert.equal(db.has(`users/${UID}/photoModeration/p1`), false);
    assert.equal(db.has(`users/${UID}/rateLimits/faceAnchorStart`), false);
    assert.equal(objects.has(SELFIE), false);
    assert.equal(objects.has(`users/${UID}/profile/photos/p1.jpg`), false);
  });

  it("touches no other member's attempt or selfie", async () => {
    await callAs(deleteUserAccount, UID);
    assert.equal(db.has(`users/${OTHER}/faceAnchor/state`), true);
    assert.equal(objects.has(OTHER_SELFIE), true);
  });

  it("verification passes once everything is gone", async () => {
    await callAs(deleteUserAccount, UID);
    const result = await verifyAccountDeletion(UID, db);
    assert.deepEqual(result.issues.filter((issue) => issue.includes("faceAnchor") || issue.includes("face-anchor")), []);
  });

  it("verification reports an attempt state that came back", async () => {
    await callAs(deleteUserAccount, UID);
    await db.doc(`users/${UID}/faceAnchor/state`).set({status: "verified"});
    const result = await verifyAccountDeletion(UID, db);
    assert.ok(result.issues.includes(`firestore_remnant:users/${UID}/faceAnchor/state`));
  });

  it("verification reports a selfie that survived", async () => {
    await callAs(deleteUserAccount, UID);
    objects.add(SELFIE);
    const result = await verifyAccountDeletion(UID, db);
    assert.equal(result.complete, false);
    assert.ok(result.issues.some((issue) => issue.includes("face-anchor/pending")), result.issues.join(","));
  });
});
