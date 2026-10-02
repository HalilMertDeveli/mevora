const {describe, it, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");
const {publishedPath} = require("./helpers/faceAnchorHarness.cjs");
const {bornYearsAgo} = require("./helpers/birthDates.cjs");

// The callable reads getFirestore() once, at module load.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});
const savedEnv = {
  FUNCTIONS_EMULATOR: process.env.FUNCTIONS_EMULATOR,
  FACE_ANCHOR_ENFORCEMENT: process.env.FACE_ANCHOR_ENFORCEMENT,
};
const {completeOnboarding} = require("../lib/onboarding.js");
const {ageFromBirthDate, publicProfileProjection} = require("../lib/profileSafety.js");
const {nextAgeChangeAt} = require("../lib/profileAge.js");

const UID = "new-member";

// Face Anchor is a separate rule with its own suite.
before(() => {
  delete process.env.FUNCTIONS_EMULATOR;
  process.env.FACE_ANCHOR_ENFORCEMENT = "off";
});

after(() => {
  for (const [key, value] of Object.entries(savedEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

const ts = (date) => Timestamp.fromDate(date);

/** A member who has filled in every onboarding step. */
function seedMember({account = {}, profile = {}} = {}) {
  const photoIds = ["p1", "p2", "p3"];
  const seed = {};
  seed[`users/${UID}`] = {uid: UID, accountStatus: "active", lastName: "Yılmaz", ...account};
  seed[`profiles/${UID}`] = {
    uid: UID,
    displayName: "Deniz",
    gender: "female",
    interestedIn: "male",
    city: "İstanbul",
    education: "bachelor",
    relationshipGoal: "long_term",
    bio: "Merhaba.",
    interests: ["music", "travel", "books"],
    lifestyleProfile: {smoking: "no", drinking: "socially", exercise: "often", pets: "dog"},
    photos: photoIds.map((id, index) => ({
      id,
      order: index,
      isPrimary: index === 0,
      moderationStatus: "approved",
      storagePath: publishedPath(UID, id),
      downloadUrl: `https://cdn.test/${id}.jpg`,
    })),
    ...profile,
  };
  for (const id of photoIds) {
    seed[`users/${UID}/photoModeration/${id}`] = {
      status: "approved",
      storagePath: publishedPath(UID, id),
      downloadUrl: `https://cdn.test/${id}.jpg`,
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

describe("completeOnboarding — the date of birth is private account data", () => {
  it("derives the public age from the account's date of birth", async () => {
    const born = bornYearsAgo(29, -40);
    db.reset(seedMember({account: {birthDate: ts(born)}}));
    const result = await callAs(completeOnboarding, UID);
    assert.equal(result.age, 29);

    const profile = db.read(`profiles/${UID}`);
    assert.equal(profile.age, 29);
    assert.equal(profile.profileCompleted, true);
    assert.equal("birthDate" in profile, false);

    const account = db.read(`users/${UID}`);
    assert.deepEqual(account.birthDate.toDate(), born);
    assert.deepEqual(account.ageRolloverAt.toDate(), nextAgeChangeAt(born, new Date()));
    assert.equal(account.lastName, "Yılmaz");
  });

  it("ignores an age the client wrote on the profile", async () => {
    db.reset(seedMember({account: {birthDate: ts(bornYearsAgo(31))}, profile: {age: 22}}));
    await callAs(completeOnboarding, UID);
    assert.equal(db.read(`profiles/${UID}`).age, 31);
  });

  it("refuses a member under 18 whatever the profile claims", async () => {
    db.reset(seedMember({account: {birthDate: ts(bornYearsAgo(18, 1))}, profile: {age: 30}}));
    await rejects(callAs(completeOnboarding, UID), "underage");
    const profile = db.read(`profiles/${UID}`);
    assert.notEqual(profile.profileCompleted, true);
    assert.equal(profile.age, 30);
  });

  it("accepts a member who turns 18 today", async () => {
    db.reset(seedMember({account: {birthDate: ts(bornYearsAgo(18))}}));
    assert.equal((await callAs(completeOnboarding, UID)).age, 18);
  });

  it("refuses an Istanbul member the day before they turn 18", async () => {
    // Midnight of tomorrow in Istanbul is 21:00 UTC today: the stored instant
    // already falls on the server's today, the birthday does not.
    db.reset(seedMember({account: {birthDate: ts(bornYearsAgo(18, 1, 3))}}));
    await rejects(callAs(completeOnboarding, UID), "underage");
    assert.notEqual(db.read(`profiles/${UID}`).profileCompleted, true);
    assert.equal("ageRolloverAt" in db.read(`users/${UID}`), false);
  });

  it("accepts an Istanbul member on the day they turn 18", async () => {
    db.reset(seedMember({account: {birthDate: ts(bornYearsAgo(18, 0, 3))}}));
    assert.equal((await callAs(completeOnboarding, UID)).age, 18);
  });

  it("schedules an Istanbul member's roll-over for the day they picked", async () => {
    const born = bornYearsAgo(29, -40, 3);
    const pickedDay = new Date(born.getTime() + 3 * 3_600_000);
    db.reset(seedMember({account: {birthDate: ts(born)}}));
    await callAs(completeOnboarding, UID);
    const marker = db.read(`users/${UID}`).ageRolloverAt.toDate();
    // Midnight UTC of that day's next anniversary. Date.UTC puts a 29 February
    // on 1 March in a common year, as the rule does.
    assert.equal(
      marker.getTime(),
      Date.UTC(marker.getUTCFullYear(), pickedDay.getUTCMonth(), pickedDay.getUTCDate()),
    );
  });

  it("refuses a new member with no date of birth, even with an age on the profile", async () => {
    db.reset(seedMember({profile: {age: 30}}));
    await rejects(callAs(completeOnboarding, UID), "underage");
    assert.notEqual(db.read(`profiles/${UID}`).profileCompleted, true);
  });

  it("moves a date left on the profile by an older app build to the account", async () => {
    const born = bornYearsAgo(27, -3);
    db.reset(seedMember({profile: {birthDate: ts(born), age: 26}}));
    await callAs(completeOnboarding, UID);

    const profile = db.read(`profiles/${UID}`);
    assert.equal("birthDate" in profile, false);
    assert.equal(profile.age, 27);
    const account = db.read(`users/${UID}`);
    assert.deepEqual(account.birthDate.toDate(), born);
    assert.ok(account.ageRolloverAt instanceof Timestamp);
  });

  it("the account's date wins over one still on the profile", async () => {
    const onAccount = bornYearsAgo(40);
    db.reset(seedMember({
      account: {birthDate: ts(onAccount)},
      profile: {birthDate: ts(bornYearsAgo(20))},
    }));
    await callAs(completeOnboarding, UID);
    assert.equal(db.read(`profiles/${UID}`).age, 40);
    assert.equal("birthDate" in db.read(`profiles/${UID}`), false);
    assert.deepEqual(db.read(`users/${UID}`).birthDate.toDate(), onAccount);
  });

  it("a member who finished before the change, with only an age, is not locked out", async () => {
    db.reset(seedMember({profile: {age: 33, profileCompleted: true, onboardingCompleted: true}}));
    const result = await callAs(completeOnboarding, UID);
    assert.equal(result.age, 33);
    assert.equal(db.read(`profiles/${UID}`).age, 33);
    assert.equal("ageRolloverAt" in db.read(`users/${UID}`), false);
  });

  it("the other onboarding checks still answer first", async () => {
    db.reset(seedMember({profile: {interests: ["music"]}}));
    await rejects(callAs(completeOnboarding, UID), "interests-required");
  });

  it("what another member is served carries the age and no date", async () => {
    const born = bornYearsAgo(29);
    db.reset(seedMember({account: {birthDate: ts(born)}}));
    await callAs(completeOnboarding, UID);
    const stored = db.read(`profiles/${UID}`);
    const projection = publicProfileProjection(stored);
    assert.equal(projection.age, ageFromBirthDate(born));
    assert.equal(JSON.stringify(stored).includes("birthDate"), false);
    assert.equal(JSON.stringify(projection).includes("birthDate"), false);
  });
});
