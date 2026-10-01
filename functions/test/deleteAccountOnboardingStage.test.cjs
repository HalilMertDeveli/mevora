const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

// deleteAccount.js binds getFirestore()/getAuth() at load, so the in-memory
// doubles go in first.
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

// Storage is resolved per call; this double records which prefixes were asked
// to go, so a photo uploaded on the photo step is seen to be covered.
const deletedPrefixes = [];
require("firebase-admin/storage").getStorage = () => ({
  bucket: () => ({
    async deleteFiles({prefix}) {
      deletedPrefixes.push(prefix);
    },
    async getFiles() {
      return [[]];
    },
  }),
});

const {deleteUserAccount} = require("../lib/deleteAccount.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");

/**
 * Deletion from the onboarding screens.
 *
 * A member who signs up and leaves before finishing onboarding has to be able
 * to delete the account from inside the app. Such an account is thinner than
 * the ones `deleteUserAccount` was written against: no completed profile, no
 * matches, no humor or music data, possibly nothing in Firestore at all. The
 * callable must still finish, take what is there, and remove the Auth record.
 */
const UID = "uid-onboarding";
const OTHER = "uid-member";

/** The member-owned documents; none of them may outlive the account. */
const OWNED_DOCS = [
  `users/${UID}`,
  `profiles/${UID}`,
  `userPreferences/${UID}`,
  `userSettings/${UID}`,
  `userPrivacy/${UID}`,
  `userLocation/${UID}`,
];

/** What the first sign-in writes, before any onboarding step is answered. */
function signedUpOnly() {
  return {
    [`users/${UID}`]: {
      uid: UID,
      id: UID,
      email: "new@example.com",
      profileCompleted: false,
      onboardingCompleted: false,
      isActive: true,
      isBanned: false,
      isVerified: false,
      accountStatus: "active",
    },
    [`profiles/${UID}`]: {
      uid: UID,
      displayName: null,
      photos: [],
      interests: [],
      languages: [],
      profileCompleted: false,
      onboardingCompleted: false,
      isDiscoverable: false,
    },
    [`userPreferences/${UID}`]: {uid: UID},
    [`userSettings/${UID}`]: {uid: UID},
    [`userPrivacy/${UID}`]: {uid: UID},
  };
}

/** Left on the photo step: a draft, a surname, photos awaiting review. */
function leftHalfway() {
  return {
    ...signedUpOnly(),
    [`users/${UID}`]: {
      uid: UID,
      id: UID,
      lastName: "Lovelace",
      profileCompleted: false,
      onboardingCompleted: false,
      accountStatus: "active",
    },
    [`profiles/${UID}`]: {
      uid: UID,
      displayName: "Ada",
      city: "İstanbul",
      interests: ["music", "travel", "food"],
      onboardingStep: "photos",
      photos: [{id: "p1", storagePath: `profiles/${UID}/photos/p1.jpg`}],
      profileCompleted: false,
      onboardingCompleted: false,
      isDiscoverable: false,
    },
    [`userLocation/${UID}`]: {uid: UID, city: "İstanbul"},
    [`users/${UID}/photoModeration/p1`]: {photoId: "p1", status: "pending"},
    [`users/${UID}/faceAnchor/state`]: {attempts: 1},
    [`users/${UID}/fcmTokens/t1`]: {token: "t1"},
    [`users/${UID}/devices/d1`]: {platform: "android"},
    [`users/${UID}/settings/language`]: {languageCode: "tr"},
  };
}

/** A finished member whose data must not be touched by someone else leaving. */
function otherMember() {
  return {
    [`users/${OTHER}`]: {uid: OTHER, onboardingCompleted: true, profileCompleted: true},
    [`profiles/${OTHER}`]: {uid: OTHER, displayName: "Grace", onboardingCompleted: true},
    [`userSettings/${OTHER}`]: {uid: OTHER},
    [`users/${OTHER}/fcmTokens/t9`]: {token: "t9"},
  };
}

function seed(docs) {
  db.reset({...docs, ...otherMember()});
  auth.users.clear();
  auth.deleted.length = 0;
  auth.addUser(UID);
  auth.addUser(OTHER);
  deletedPrefixes.length = 0;
}

function assertNothingOwnedRemains() {
  const remaining = db.paths();
  for (const path of OWNED_DOCS) {
    assert.equal(remaining.includes(path), false, `left behind: ${path}`);
  }
  for (const path of remaining) {
    assert.equal(path.startsWith(`users/${UID}/`), false, `left behind: ${path}`);
  }
}

describe("account deletion before onboarding is finished", () => {
  for (const [stage, docs] of [
    ["right after sign-up, with no step answered", signedUpOnly],
    ["halfway, with a draft and uploaded photos", leftHalfway],
  ]) {
    describe(stage, () => {
      beforeEach(() => seed(docs()));

      it("reports the account deleted", async () => {
        const result = await callAs(deleteUserAccount, UID);

        // The app signs the member out only on exactly this answer.
        assert.equal(result.ok, true);
        assert.equal(result.deleted, true);
      });

      it("removes the Auth record and every document the member owned", async () => {
        await callAs(deleteUserAccount, UID);

        assert.equal(auth.users.has(UID), false);
        assert.deepEqual(auth.deleted, [UID]);
        assertNothingOwnedRemains();
      });

      it("clears the member's storage, uploaded photos included", async () => {
        await callAs(deleteUserAccount, UID);

        for (const prefix of [
          `users/${UID}/`,
          `profiles/${UID}/`,
          `moderation/quarantine/${UID}/`,
          `face-anchor/pending/${UID}/`,
        ]) {
          assert.ok(deletedPrefixes.includes(prefix), `storage prefix kept: ${prefix}`);
        }
      });

      it("leaves other members alone", async () => {
        await callAs(deleteUserAccount, UID);

        assert.equal(auth.users.has(OTHER), true);
        for (const [path, data] of Object.entries(otherMember())) {
          assert.deepEqual(db.read(path), data, path);
        }
      });

      it("passes the post-deletion verification, also after a retry", async () => {
        await callAs(deleteUserAccount, UID);
        // A double tap on "Delete forever", or a retry after a dropped reply.
        const again = await callAs(deleteUserAccount, UID);
        assert.equal(again.deleted, true);

        const verified = await verifyAccountDeletion(UID, db);
        assert.deepEqual(verified.issues, []);
        assert.equal(verified.complete, true);
      });
    });
  }

  it("deletes an account that has an Auth record and nothing else", async () => {
    // The first sign-in writes its documents after the Auth record exists; a
    // member can be signed in with that write never having landed.
    seed({});

    const result = await callAs(deleteUserAccount, UID);

    assert.equal(result.ok, true);
    assert.equal(result.deleted, true);
    assert.equal(auth.users.has(UID), false);
    assertNothingOwnedRemains();
    const verified = await verifyAccountDeletion(UID, db);
    assert.deepEqual(verified.issues, []);
  });

  it("refuses a caller who is not signed in", async () => {
    seed(signedUpOnly());

    await assert.rejects(
      () => callAs(deleteUserAccount, null),
      (error) => error.code === "unauthenticated",
    );
    assert.equal(auth.users.has(UID), true);
    assert.equal(db.paths().includes(`users/${UID}`), true);
  });
});
