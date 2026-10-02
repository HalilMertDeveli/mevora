const {describe, it, beforeEach, after} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");
const {publishedPath, verdict} = require("./helpers/faceAnchorHarness.cjs");

// The callable reads getFirestore() once, at module load.
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});
const savedEnv = {
  FUNCTIONS_EMULATOR: process.env.FUNCTIONS_EMULATOR,
  FACE_ANCHOR_ENFORCEMENT: process.env.FACE_ANCHOR_ENFORCEMENT,
};
const {completeOnboarding} = require("../lib/onboarding.js");
const {getIncomingLikes} = require("../lib/incomingLikes.js");
const {getFaceAnchorRequirements} = require("../lib/faceAnchor/functions.js");
const {FACE_ANCHOR_CONSENT_VERSION} = require("../lib/faceAnchor/faceAnchorRecord.js");

const UID = "new-member";

function setEnforcement(value) {
  delete process.env.FUNCTIONS_EMULATOR;
  if (value === undefined) delete process.env.FACE_ANCHOR_ENFORCEMENT;
  else process.env.FACE_ANCHOR_ENFORCEMENT = value;
}

after(() => {
  for (const [key, value] of Object.entries(savedEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

/**
 * A member who has filled in every onboarding step. `anchors` are the photo
 * ids the server has verified; `photos` is what the client wrote.
 */
function seedMember({uid = UID, photoIds = ["p1", "p2", "p3"], anchors = [], profile = {}, ledger = {}, photos} = {}) {
  const seed = {};
  // The surname and the date of birth are private account data.
  seed[`users/${uid}`] = {
    uid,
    accountStatus: "active",
    lastName: "Yılmaz",
    birthDate: Timestamp.fromDate(new Date(1996, 3, 11)),
  };
  seed[`profiles/${uid}`] = {
    uid,
    displayName: "Deniz",
    gender: "female",
    interestedIn: "male",
    city: "İstanbul",
    education: "bachelor",
    relationshipGoal: "long_term",
    bio: "Merhaba.",
    interests: ["music", "travel", "books"],
    lifestyleProfile: {smoking: "no", drinking: "socially", exercise: "often", pets: "dog"},
    photos: photos ?? photoIds.map((id, index) => ({
      id,
      order: index,
      isPrimary: index === 0,
      moderationStatus: "approved",
      storagePath: publishedPath(uid, id),
      downloadUrl: `https://cdn.test/${id}.jpg`,
    })),
    ...profile,
  };
  for (const id of photoIds) {
    seed[`users/${uid}/photoModeration/${id}`] = {
      status: "approved",
      storagePath: publishedPath(uid, id),
      downloadUrl: `https://cdn.test/${id}.jpg`,
      ...(anchors.includes(id) ? {faceAnchor: verdict(uid, id)} : {}),
      ...(ledger[id] ?? {}),
    };
  }
  return seed;
}

async function rejects(promise, message) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.message, message);
    return true;
  });
}

describe("completeOnboarding — Face Anchor enforced", () => {
  beforeEach(() => setEnforcement("on"));

  it("three approved photos and no anchor: refused", async () => {
    db.reset(seedMember());
    await rejects(callAs(completeOnboarding, UID), "face-anchor-required");
    const profile = db.read(`profiles/${UID}`);
    assert.notEqual(profile.profileCompleted, true);
    assert.notEqual(profile.isDiscoverable, true);
    assert.equal(profile.faceAnchorRequired, undefined);
  });

  it("three photos with one verified anchor: completes, and is put under the rule", async () => {
    db.reset(seedMember({anchors: ["p2"]}));
    const result = await callAs(completeOnboarding, UID);
    assert.equal(result.ok, true);
    const profile = db.read(`profiles/${UID}`);
    assert.equal(profile.profileCompleted, true);
    assert.equal(profile.isDiscoverable, true);
    assert.equal(profile.faceAnchorRequired, true);
    assert.deepEqual(profile.faceAnchorPhotoIds, ["p2"]);
    // The anchor is the primary photo whatever order the client left.
    assert.equal(profile.photos[0].id, "p2");
    assert.equal(profile.photos[0].isPrimary, true);
    assert.equal(profile.photos[0].faceAnchorVerified, true);
    assert.equal(db.read(`users/${UID}`).profileCompleted, true);
  });

  it("a client-written faceAnchorVerified does not satisfy it", async () => {
    const seed = seedMember();
    seed[`profiles/${UID}`].photos[0].faceAnchorVerified = true;
    seed[`profiles/${UID}`].faceAnchorPhotoIds = ["p1"];
    db.reset(seed);
    await rejects(callAs(completeOnboarding, UID), "face-anchor-required");
  });

  it("an anchor held in review does not count", async () => {
    db.reset(seedMember({anchors: ["p1"], ledger: {p1: {status: "manual_review"}}}));
    await rejects(callAs(completeOnboarding, UID), "face-anchor-required");
  });

  it("an anchor that was removed from the profile is restored and counts", async () => {
    const seed = seedMember({photoIds: ["p1", "p2", "p3", "p4"], anchors: ["p1"]});
    seed[`profiles/${UID}`].photos = seed[`profiles/${UID}`].photos.filter((p) => p.id !== "p1");
    db.reset(seed);
    await callAs(completeOnboarding, UID);
    assert.equal(db.read(`profiles/${UID}`).photos[0].id, "p1");
  });

  it("secondary photos need no face check", async () => {
    db.reset(seedMember({anchors: ["p1"]}));
    await callAs(completeOnboarding, UID);
    const photos = db.read(`profiles/${UID}`).photos;
    assert.equal(photos.length, 3);
    assert.equal(photos.filter((p) => p.faceAnchorVerified === true).length, 1);
  });

  it("the same photo id written three times is one photo", async () => {
    const seed = seedMember({photoIds: ["p1"], anchors: ["p1"]});
    const one = seed[`profiles/${UID}`].photos[0];
    seed[`profiles/${UID}`].photos = [one, {...one}, {...one}];
    db.reset(seed);
    await rejects(callAs(completeOnboarding, UID), "photos-required");
  });

  it("does not write back a stale photos array", async () => {
    // The ledger rejected p3 after the client last wrote the array.
    db.reset(seedMember({photoIds: ["p1", "p2", "p3", "p4"], anchors: ["p1"], ledger: {p3: {status: "rejected"}}}));
    await callAs(completeOnboarding, UID);
    const profile = db.read(`profiles/${UID}`);
    assert.equal(profile.photos.find((p) => p.id === "p3").moderationStatus, "rejected");
    assert.equal(profile.profileModerationStatus, "rejected");
  });
});

describe("completeOnboarding — members who finished before the rule", () => {
  beforeEach(() => setEnforcement("on"));

  it("calling it again does not put them under the rule or lock them out", async () => {
    db.reset(seedMember({profile: {profileCompleted: true, onboardingCompleted: true, isDiscoverable: true}}));
    const result = await callAs(completeOnboarding, UID);
    assert.equal(result.ok, true);
    assert.equal(db.read(`profiles/${UID}`).faceAnchorRequired, undefined);
  });

  it("their photos are not treated as verified", async () => {
    db.reset(seedMember({profile: {profileCompleted: true}}));
    await callAs(completeOnboarding, UID);
    const profile = db.read(`profiles/${UID}`);
    assert.equal(profile.photos.some((p) => p.faceAnchorVerified === true), false);
    assert.equal(profile.faceAnchorPhotoIds, undefined);
  });

  it("completion flags on users/{uid} do not make a new member a legacy one", async () => {
    // users/{uid}.profileCompleted is client-writable at create; only the
    // profile's flag, which the server writes, is read.
    const seed = seedMember();
    seed[`users/${UID}`].profileCompleted = true;
    seed[`users/${UID}`].onboardingCompleted = true;
    db.reset(seed);
    await rejects(callAs(completeOnboarding, UID), "face-anchor-required");
  });

  it("a member already under the rule stays under it", async () => {
    db.reset(seedMember({profile: {profileCompleted: true, faceAnchorRequired: true}}));
    await rejects(callAs(completeOnboarding, UID), "face-anchor-required");
  });
});

describe("completeOnboarding — enforcement off", () => {
  beforeEach(() => setEnforcement(undefined));

  it("completes without an anchor and is not put under the rule", async () => {
    db.reset(seedMember());
    const result = await callAs(completeOnboarding, UID);
    assert.equal(result.ok, true);
    const profile = db.read(`profiles/${UID}`);
    assert.equal(profile.profileCompleted, true);
    assert.equal(profile.faceAnchorRequired, undefined);
  });

  it("the other onboarding checks are unchanged", async () => {
    db.reset(seedMember({photoIds: ["p1", "p2"]}));
    await rejects(callAs(completeOnboarding, UID), "photos-required");
    const seed = seedMember();
    delete seed[`users/${UID}`].lastName;
    db.reset(seed);
    await rejects(callAs(completeOnboarding, UID), "last-name-required");
    db.reset({});
    await rejects(callAs(completeOnboarding, UID), "profile-missing");
  });
});

describe("getFaceAnchorRequirements — what the app is told", () => {
  it("requires sign-in", async () => {
    await assert.rejects(callAs(getFaceAnchorRequirements, null));
  });

  it("a new member under enforcement: required; no provider configured: unavailable", async () => {
    setEnforcement("on");
    db.reset(seedMember());
    assert.deepEqual(await callAs(getFaceAnchorRequirements, UID), {
      required: true,
      available: false,
      consentVersion: FACE_ANCHOR_CONSENT_VERSION,
    });
  });

  it("the emulator has the fake provider and enforces by default", async () => {
    setEnforcement(undefined);
    process.env.FUNCTIONS_EMULATOR = "true";
    db.reset(seedMember());
    const result = await callAs(getFaceAnchorRequirements, UID);
    assert.equal(result.required, true);
    assert.equal(result.available, true);
  });

  it("a member who finished before the rule is not told it is required", async () => {
    setEnforcement("on");
    db.reset(seedMember({profile: {profileCompleted: true}}));
    assert.equal((await callAs(getFaceAnchorRequirements, UID)).required, false);
  });

  it("carries nothing a client could use to pick a provider or an outcome", async () => {
    setEnforcement("on");
    db.reset(seedMember());
    const result = await callAs(getFaceAnchorRequirements, UID, {testMode: true, provider: "fake"});
    assert.deepEqual(Object.keys(result).sort(), ["available", "consentVersion", "required"]);
    assert.equal(result.available, false);
  });
});

describe("Likes You — a liker whose anchor dropped is not shown", () => {
  const VIEWER = "viewer";

  function seedLikes(likerProfile) {
    const liker = seedMember({uid: "liker", ...likerProfile});
    const viewer = seedMember({uid: VIEWER});
    // Likes You shows profiles to Premium members only.
    auth.users.set(VIEWER, {uid: VIEWER, customClaims: {premium: true}});
    return {
      ...liker,
      ...viewer,
      "likes/liker_viewer": {
        fromUserId: "liker",
        toUserId: VIEWER,
        action: "like",
        createdAt: new Date(),
      },
    };
  }

  it("a liker under the rule with no anchor is left out", async () => {
    db.reset(seedLikes({profile: {profileCompleted: true, isDiscoverable: true, faceAnchorRequired: true, faceAnchorPhotoIds: []}}));
    const result = await callAs(getIncomingLikes, VIEWER);
    assert.equal(result.isPremium, true);
    assert.deepEqual(result.items.map((i) => i.uid), []);
  });

  it("a liker with a verified primary anchor is shown", async () => {
    db.reset(seedLikes({
      anchors: ["p1"],
      profile: {profileCompleted: true, isDiscoverable: true, faceAnchorRequired: true, faceAnchorPhotoIds: ["p1"]},
    }));
    const result = await callAs(getIncomingLikes, VIEWER);
    assert.equal(result.isPremium, true);
    assert.deepEqual(result.items.map((i) => i.uid), ["liker"]);
  });
});
