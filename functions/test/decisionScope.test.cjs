const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * A like or pass is accepted only for someone the member was actually shown:
 * a Pick in their current batch, or — for Premium — someone on Likes You.
 *
 * Both decision callables (recordDiscoveryDecision, which the app calls, and
 * the legacy recordSwipe) run here end to end against the in-memory
 * Firestore, so a refusal is proven to write nothing and an accepted decision
 * is proven to keep the Picks mirror and its idempotency.
 */

// backend.js registers a Storage trigger at load, which needs a bucket name.
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-decision-scope",
  storageBucket: "demo-decision-scope.appspot.com",
});
process.env.GCLOUD_PROJECT = "demo-decision-scope";

// The callables bind getFirestore() / getAuth() at load, so the doubles go first.
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

// A like with no reciprocal one notifies the liked member, which adds an
// in-app notification with an auto id. The double has no `add`; give its
// collections one here rather than widening the shared helper.
let autoId = 0;
const collection = db.collection.bind(db);
db.collection = (path) => {
  const ref = collection(path);
  ref.add ??= async (data) => {
    const doc = ref.doc(`auto_${++autoId}`);
    await doc.set(data);
    return doc;
  };
  return ref;
};

const lifecycle = require("../lib/picks/lifecycle.js");
const {offeredDecisionSource} = require("../lib/picks/decisionScope.js");
const {picksDocPath} = require("../lib/picks/service.js");
const {recordDiscoveryDecision} = require("../lib/backend.js");
const {recordSwipe} = require("../lib/social.js");

const VIEWER = "viewer";
const approvedPhotos = [1, 2, 3].map((n) => ({
  id: `p${n}`,
  downloadUrl: `https://example.test/${n}.jpg`,
  moderationStatus: "approved",
  order: n,
}));

function profile(uid, overrides = {}) {
  return {
    uid,
    displayName: uid,
    age: 28,
    gender: "man",
    interestedIn: "women",
    isDiscoverable: true,
    profileCompleted: true,
    photos: approvedPhotos,
    lastActiveAt: Timestamp.fromMillis(Date.now()),
    ...overrides,
  };
}

/** Today's batch for the viewer, holding `uids` as active Picks. */
function batchOf(uids, {cooldowns = {}} = {}) {
  const nowMs = Date.now();
  const composed = uids.map((uid, rank) => ({
    candidateUid: uid,
    rank,
    pickType: "bestOverall",
    labels: ["bestOverall"],
    reasons: [],
    overallScore: 80,
    isBoosted: false,
    selectionStrategy: "exploit",
  }));
  return lifecycle.newBatch({
    generationId: "gen1",
    nowMs,
    picks: lifecycle.buildStoredPicks("gen1", composed, new Map(), nowMs),
    cooldowns,
  });
}

/**
 * The viewer (a woman looking for men) and a set of eligible men. Only
 * `pick1` and `pick2` are in her batch; `stranger` is equally eligible but
 * was never shown to her.
 */
function seedWorld({batch = batchOf(["pick1", "pick2"]), extra = {}} = {}) {
  const seed = {
    [`users/${VIEWER}`]: {uid: VIEWER},
    [`profiles/${VIEWER}`]: profile(VIEWER, {gender: "woman", interestedIn: "men"}),
    ...(batch ? {[picksDocPath(VIEWER)]: batch} : {}),
  };
  for (const uid of ["pick1", "pick2", "stranger", "liker"]) {
    seed[`users/${uid}`] = {uid};
    seed[`profiles/${uid}`] = profile(uid);
  }
  db.reset({...seed, ...extra});
  auth.users.clear();
}

function setPremium(uid) {
  auth.users.set(uid, {uid, customClaims: {premium: true}});
}

async function refusal(promise) {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  assert.fail("the decision was accepted");
}

async function exists(path) {
  return (await db.doc(path).get()).exists;
}

async function pickState(candidateUid) {
  const batch = lifecycle.parseBatch((await db.doc(picksDocPath(VIEWER)).get()).data());
  return batch?.picks.find((pick) => pick.candidateUid === candidateUid)?.state ?? null;
}

describe("offeredDecisionSource", () => {
  beforeEach(() => seedWorld());

  it("names Picks for anyone in the current batch", async () => {
    const source = await offeredDecisionSource({db, viewerUid: VIEWER, candidateUid: "pick1"});
    assert.equal(source, "pick");
  });

  it("counts a Pick in any state, not just active", async () => {
    const batch = batchOf(["pick1", "pick2"]);
    const decided = lifecycle.applyDecision(batch, "pick1", "passed", Date.now()).batch;
    seedWorld({batch: decided});
    assert.equal(await pickState("pick1"), "passed");
    const source = await offeredDecisionSource({db, viewerUid: VIEWER, candidateUid: "pick1"});
    assert.equal(source, "pick");
  });

  it("does not count someone who is only cooling down from an earlier batch", async () => {
    seedWorld({batch: batchOf(["pick1"], {cooldowns: {stranger: Date.now() + 86_400_000}})});
    const source = await offeredDecisionSource({db, viewerUid: VIEWER, candidateUid: "stranger"});
    assert.equal(source, null);
  });

  it("offers nothing when there is no readable batch", async () => {
    seedWorld({batch: null});
    assert.equal(await offeredDecisionSource({db, viewerUid: VIEWER, candidateUid: "pick1"}), null);
    seedWorld({batch: {...batchOf(["pick1"]), schemaVersion: -1}});
    assert.equal(await offeredDecisionSource({db, viewerUid: VIEWER, candidateUid: "pick1"}), null);
  });

  it("names Likes You for a Premium member's liker", async () => {
    seedWorld({extra: {"likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "like"}}});
    const source = await offeredDecisionSource({
      db,
      viewerUid: VIEWER,
      candidateUid: "liker",
      isPremium: async () => true,
    });
    assert.equal(source, "incomingLike");
  });

  it("counts a super like as a liker too", async () => {
    seedWorld({extra: {"likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "superLike"}}});
    const source = await offeredDecisionSource({
      db,
      viewerUid: VIEWER,
      candidateUid: "liker",
      isPremium: async () => true,
    });
    assert.equal(source, "incomingLike");
  });

  it("does not offer a liker to a free member, who is never shown them", async () => {
    seedWorld({extra: {"likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "like"}}});
    const source = await offeredDecisionSource({
      db,
      viewerUid: VIEWER,
      candidateUid: "liker",
      isPremium: async () => false,
    });
    assert.equal(source, null);
  });

  it("does not treat a pass on the member as a like", async () => {
    seedWorld({extra: {"likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "pass"}}});
    let asked = false;
    const source = await offeredDecisionSource({
      db,
      viewerUid: VIEWER,
      candidateUid: "liker",
      isPremium: async () => {
        asked = true;
        return true;
      },
    });
    assert.equal(source, null);
    assert.equal(asked, false, "no like, so no entitlement read either");
  });

  it("does not count the member's own like as incoming", async () => {
    seedWorld({extra: {"likes/viewer_stranger": {fromUserId: VIEWER, toUserId: "stranger", action: "like"}}});
    const source = await offeredDecisionSource({
      db,
      viewerUid: VIEWER,
      candidateUid: "stranger",
      isPremium: async () => true,
    });
    assert.equal(source, null);
  });
});

const CALLABLES = [
  ["recordDiscoveryDecision", recordDiscoveryDecision, (uid, action) => ({candidateUid: uid, action})],
  ["recordSwipe", recordSwipe, (uid, action) => ({targetUserId: uid, action})],
];

for (const [name, callable, payload] of CALLABLES) {
  describe(`${name} is bound to what the member was shown`, () => {
    beforeEach(() => seedWorld());

    it("accepts a like on a Pick and moves the Pick to liked", async () => {
      const result = await callAs(callable, VIEWER, payload("pick1", "like"));
      assert.equal(result.matched, false);
      assert.equal((await db.doc("likes/viewer_pick1").get()).data().action, "like");
      assert.equal(await pickState("pick1"), "liked");
      assert.equal(await pickState("pick2"), "active");
    });

    it("accepts a pass on a Pick and moves the Pick to passed", async () => {
      const result = await callAs(callable, VIEWER, payload("pick2", "pass"));
      assert.equal(result.matched, false);
      assert.equal((await db.doc("likes/viewer_pick2").get()).data().action, "pass");
      assert.equal(await pickState("pick2"), "passed");
    });

    it("stays idempotent: a repeated like on a decided Pick is still in scope", async () => {
      await callAs(callable, VIEWER, payload("pick1", "like"));
      // recordDiscoveryDecision rewrites the same like; recordSwipe has always
      // answered a replay with already-swiped. Neither may become a scope refusal.
      let again;
      try {
        again = await callAs(callable, VIEWER, payload("pick1", "like"));
      } catch (error) {
        assert.equal(name, "recordSwipe", `unexpected refusal: ${error.message}`);
        assert.equal(error.message, "already-swiped");
      }
      if (again) assert.equal(again.matched, false);
      assert.equal(await pickState("pick1"), "liked");
      const likes = await db.collection("likes").where("fromUserId", "==", VIEWER).get();
      assert.equal(likes.size, 1, "one like document, however often it is sent");
    });

    it("refuses a like on an eligible stranger and writes nothing", async () => {
      const error = await refusal(callAs(callable, VIEWER, payload("stranger", "like")));
      assert.equal(error.code, "failed-precondition");
      assert.equal(error.message, "candidate-not-offered");
      assert.equal(await exists("likes/viewer_stranger"), false);
    });

    it("refuses a pass on an eligible stranger and writes nothing", async () => {
      const error = await refusal(callAs(callable, VIEWER, payload("stranger", "pass")));
      assert.equal(error.message, "candidate-not-offered");
      assert.equal(await exists("likes/viewer_stranger"), false);
      assert.equal(await exists(`users/${VIEWER}/passedUsers/stranger`), false);
    });

    it("refuses before eligibility, so the reason says nothing about the stranger", async () => {
      seedWorld({extra: {"profiles/stranger": profile("stranger", {isDiscoverable: false})}});
      const error = await refusal(callAs(callable, VIEWER, payload("stranger", "like")));
      assert.equal(error.message, "candidate-not-offered");
    });

    it("still applies eligibility to a Pick that has since become unavailable", async () => {
      seedWorld({extra: {"profiles/pick1": profile("pick1", {isDiscoverable: false})}});
      const error = await refusal(callAs(callable, VIEWER, payload("pick1", "like")));
      assert.equal(error.message, "candidate-unavailable");
      assert.equal(await exists("likes/viewer_pick1"), false);
    });

    it("refuses everyone when the member has no Picks batch", async () => {
      seedWorld({batch: null});
      const error = await refusal(callAs(callable, VIEWER, payload("pick1", "like")));
      assert.equal(error.message, "candidate-not-offered");
    });

    it("lets a Premium member like back someone from Likes You, and they match", async () => {
      seedWorld({
        extra: {
          "likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "like"},
        },
      });
      setPremium(VIEWER);
      const result = await callAs(callable, VIEWER, payload("liker", "like"));
      assert.equal(result.matched, true);
      assert.equal((await db.doc("matches/liker_viewer").get()).data().isActive, true);
      // Not a Pick, so the Picks mirror has nothing to move.
      assert.equal(await pickState("liker"), null);
    });

    it("lets a Premium member pass on someone from Likes You", async () => {
      seedWorld({
        extra: {
          "likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "like"},
        },
      });
      setPremium(VIEWER);
      const result = await callAs(callable, VIEWER, payload("liker", "pass"));
      assert.equal(result.matched, false);
      assert.equal((await db.doc("likes/viewer_liker").get()).data().action, "pass");
    });

    it("refuses a free member's hand-made like on a liker they were never shown", async () => {
      seedWorld({
        extra: {
          "likes/liker_viewer": {fromUserId: "liker", toUserId: VIEWER, action: "like"},
        },
      });
      const error = await refusal(callAs(callable, VIEWER, payload("liker", "like")));
      assert.equal(error.message, "candidate-not-offered");
      assert.equal(await exists("matches/liker_viewer"), false);
    });

    it("keeps refusing an active match partner as already-matched", async () => {
      seedWorld({
        extra: {
          "matches/pick1_viewer": {userIds: ["pick1", VIEWER], isActive: true},
        },
      });
      const error = await refusal(callAs(callable, VIEWER, payload("pick1", "like")));
      assert.equal(error.message, "already-matched");
    });
  });
}
