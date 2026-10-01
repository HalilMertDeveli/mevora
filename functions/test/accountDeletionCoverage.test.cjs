const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

// deleteAccount.js binds getFirestore()/getAuth() at load, so the doubles go first.
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});
const {deleteUserAccount} = require("../lib/deleteAccount.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");

/**
 * Firestore does not cascade: deleting users/{uid} leaves every subcollection
 * under it in place, so account deletion names each one. A subcollection added
 * without a line there survives the account silently — `boostReach` (one row
 * per member who saw a boosted profile) did, and so did the uid-keyed Spotify
 * rate-limit counters.
 */
const UID = "uid-leaving";
const OTHER = "uid-staying";

/** Subcollections of users/{userId} the security rules know about, with a document id to seed. */
function userSubcollectionsInRules() {
  const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firebase", "firestore.rules"),
    "utf8",
  );
  const lines = rules.split(/\r?\n/);
  const start = lines.findIndex((line) => /^\s*match \/users\/\{userId\} \{/.test(line));
  const end = lines.findIndex((line, index) => index > start && /^\s*match \/profiles\/\{userId\} \{/.test(line));
  assert.ok(start > -1 && end > start, "users block not found in firestore.rules");
  const found = [];
  for (const line of lines.slice(start + 1, end)) {
    const match = /^\s*match \/([A-Za-z]+)\/(\{[A-Za-z]+\}|[A-Za-z]+) \{/.exec(line);
    if (match) {
      found.push({name: match[1], docId: match[2].startsWith("{") ? null : match[2]});
    }
  }
  return found;
}

// Server-written, single-document subcollections: only this id ever exists.
const FIXED_DOC_IDS = {relationshipMatch: "summary"};
// Written with the Admin SDK only, so the rules never mention them.
const SERVER_ONLY = ["mevoraPicks", "dailyStreak"];

describe("account deletion covers every users/{uid} subcollection", () => {
  const inRules = userSubcollectionsInRules();
  const subcollections = [
    ...inRules.map(({name, docId}) => ({name, docId: docId ?? FIXED_DOC_IDS[name] ?? "doc-1"})),
    ...SERVER_ONLY.map((name) => ({name, docId: "current"})),
  ];

  beforeEach(() => {
    const seed = {
      [`users/${UID}`]: {uid: UID},
      [`profiles/${UID}`]: {uid: UID},
      [`users/${OTHER}`]: {uid: OTHER},
    };
    for (const {name, docId} of subcollections) {
      seed[`users/${UID}/${name}/${docId}`] = {seeded: name};
      seed[`users/${OTHER}/${name}/${docId}`] = {seeded: name};
    }
    db.reset(seed);
    auth.users.clear();
    auth.addUser(UID);
    auth.addUser(OTHER);
  });

  it("reads the subcollection list from the rules", () => {
    // A rules reformat must fail here, not turn the test below into a no-op.
    assert.ok(inRules.length >= 31, `only parsed ${inRules.length} subcollections`);
    assert.ok(inRules.some(({name}) => name === "boostReach"));
    assert.ok(inRules.some(({name, docId}) => name === "presence" && docId === "current"));
  });

  it("leaves nothing under users/{uid}", async () => {
    await callAs(deleteUserAccount, UID);

    const left = db.paths().filter((p) => p === `users/${UID}` || p.startsWith(`users/${UID}/`));
    assert.deepEqual(left, []);
  });

  it("leaves another member's subcollections alone", async () => {
    await callAs(deleteUserAccount, UID);

    for (const {name, docId} of subcollections) {
      assert.deepEqual(db.read(`users/${OTHER}/${name}/${docId}`), {seeded: name}, name);
    }
  });
});

describe("account deletion erases Boost reach rows and rate-limit counters", () => {
  function seedBoostedMember() {
    db.reset({
      [`users/${UID}`]: {uid: UID},
      [`profiles/${UID}`]: {uid: UID},
      [`users/${UID}/boosts/b1`]: {boostId: "b1", userId: UID, totalImpressions: 2, uniqueUsersReached: 2},
      [`users/${UID}/boostReach/viewerkey1`]: {boostId: "b1", impressions: 1, likedAt: null, matchedAt: null},
      [`users/${UID}/boostReach/viewerkey2`]: {boostId: "b1", impressions: 4, likedAt: null, matchedAt: null},
      [`authRateLimits/spotify_${UID}`]: {windowStart: 1, count: 3},
      [`authRateLimits/spotify_link_${UID}`]: {windowStart: 1, count: 1},
      [`users/${OTHER}`]: {uid: OTHER},
      [`users/${OTHER}/boostReach/viewerkey9`]: {boostId: "b9", impressions: 1},
      [`authRateLimits/spotify_${OTHER}`]: {windowStart: 1, count: 2},
      [`authRateLimits/spotify_link_${OTHER}`]: {windowStart: 1, count: 2},
    });
    auth.users.clear();
    auth.addUser(UID);
    auth.addUser(OTHER);
  }

  beforeEach(seedBoostedMember);

  it("removes every boostReach row of the deleted member", async () => {
    await callAs(deleteUserAccount, UID);

    assert.deepEqual(db.paths().filter((p) => p.startsWith(`users/${UID}/boostReach/`)), []);
    assert.deepEqual(db.read(`users/${OTHER}/boostReach/viewerkey9`), {boostId: "b9", impressions: 1});
  });

  it("removes the rate-limit counters keyed by the deleted uid", async () => {
    await callAs(deleteUserAccount, UID);

    assert.equal(db.read(`authRateLimits/spotify_${UID}`), undefined);
    assert.equal(db.read(`authRateLimits/spotify_link_${UID}`), undefined);
    assert.equal(db.read(`authRateLimits/spotify_${OTHER}`).count, 2);
    assert.equal(db.read(`authRateLimits/spotify_link_${OTHER}`).count, 2);
  });

  it("verification passes after a real deletion", async () => {
    await callAs(deleteUserAccount, UID);

    const verified = await verifyAccountDeletion(UID, db);
    assert.deepEqual(verified.issues, []);
    assert.equal(verified.complete, true);
  });

  it("verification reports boost rows and counters that survived", async () => {
    // What a Discover page already in flight can write after the sweep: the
    // impression batch sets the reach row and merges into the boost session.
    db.reset({
      [`users/${UID}/boosts/b1`]: {totalImpressions: 1},
      [`users/${UID}/boostReach/viewerkey1`]: {boostId: "b1", impressions: 1},
      [`authRateLimits/spotify_${UID}`]: {windowStart: 1, count: 3},
      [`authRateLimits/spotify_link_${UID}`]: {windowStart: 1, count: 1},
    });
    auth.users.clear();

    const verified = await verifyAccountDeletion(UID, db);

    assert.equal(verified.complete, false);
    for (const issue of [
      "boosts_remnant",
      "boost_reach_remnant",
      `firestore_remnant:authRateLimits/spotify_${UID}`,
      `firestore_remnant:authRateLimits/spotify_link_${UID}`,
    ]) {
      assert.ok(verified.issues.includes(issue), `missing ${issue} in ${verified.issues}`);
    }
  });

  it("verification does not mistake another member's rows for remnants", async () => {
    db.reset({
      [`users/${OTHER}/boosts/b9`]: {totalImpressions: 1},
      [`users/${OTHER}/boostReach/viewerkey9`]: {boostId: "b9", impressions: 1},
      [`authRateLimits/spotify_${OTHER}`]: {windowStart: 1, count: 2},
    });
    auth.users.clear();

    const verified = await verifyAccountDeletion(UID, db);

    assert.deepEqual(verified.issues, []);
  });
});
