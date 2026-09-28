const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const {
  loadPersonalizationContext,
  pairScores,
  personalizationProfilePath,
  recordLearningEvent,
  recordLearningEventSafely,
} = require("../lib/personalization/store.js");
const {SIGNAL_STRENGTHS, WEAK_SIGNALS} = require("../lib/personalization/config.js");
const {
  debugPersonalizationRanking,
  personalizationOnDecision,
  personalizationOnMatchCreated,
  recordProfileEngagement,
} = require("../lib/personalization/functions.js");

const HUMOR_HIGH = {relationship: 50, values: 50, lifestyle: 50, interests: 50, music: 50, humor: 95};
const NOW = Date.UTC(2026, 8, 1, 12, 0, 0);

async function humorAdjustment(uid) {
  const snap = await db.doc(personalizationProfilePath(uid)).get();
  return snap.data()?.dimensions?.humor?.adjustment ?? 1;
}

function profileDoc(extra = {}) {
  return {
    relationshipGoal: "longTerm",
    interests: ["travel", "books", "coffee"],
    lifestyle: ["pets:dog", "smoking:never"],
    ...extra,
  };
}

function writeEvent(before, after, params = {}) {
  const snap = (data) => ({exists: data !== undefined, data: () => data});
  return {data: {before: snap(before), after: snap(after)}, params};
}

beforeEach(() => {
  db.reset({
    "profiles/viewer": profileDoc(),
    "profiles/cand": profileDoc({interests: ["travel", "books", "chess"]}),
  });
});

describe("recording learning events", () => {
  it("applies an event once, however many times it is delivered", async () => {
    const input = {
      actorUid: "viewer", otherUid: "cand", type: "match", key: "m1",
      strength: SIGNAL_STRENGTHS.match, vector: HUMOR_HIGH, nowMs: NOW,
    };
    const first = await recordLearningEvent(db, input);
    const after1 = await humorAdjustment("viewer");
    const second = await recordLearningEvent(db, input);
    const third = await recordLearningEventSafely(db, input);
    assert.equal(first.outcome, "applied");
    assert.equal(second.outcome, "duplicate");
    assert.equal(third, "duplicate");
    assert.ok(after1 > 1);
    assert.equal(await humorAdjustment("viewer"), after1);
    const stored = (await db.doc(personalizationProfilePath("viewer")).get()).data();
    assert.equal(stored.eventCount, 1);
    assert.equal(stored.algorithmVersion, 1);
  });

  it("drops events while the member has personalization switched OFF, and resumes when ON", async () => {
    await db.doc("userSettings/viewer").set({personalizeRecommendations: false});
    const off = await recordLearningEvent(db, {
      actorUid: "viewer", otherUid: "cand", type: "match", key: "m1", strength: 2, vector: HUMOR_HIGH,
    });
    assert.equal(off.outcome, "disabled");
    assert.equal((await db.doc(personalizationProfilePath("viewer")).get()).exists, false);

    await db.doc("userSettings/viewer").set({personalizeRecommendations: true}, {merge: true});
    const on = await recordLearningEvent(db, {
      actorUid: "viewer", otherUid: "cand", type: "match", key: "m1", strength: 2, vector: HUMOR_HIGH,
    });
    assert.equal(on.outcome, "applied", "an event dropped while OFF is not a duplicate later");
  });

  it("budgets weak events per day", async () => {
    for (let i = 0; i < WEAK_SIGNALS.maxEventsPerDay; i++) {
      const r = await recordLearningEvent(db, {
        actorUid: "viewer", otherUid: `c${i}`, type: "profileEngagement", key: "2026-09-01",
        strength: 0.1, weak: true, vector: HUMOR_HIGH, nowMs: NOW,
      });
      assert.equal(r.outcome, "applied");
    }
    const capped = await recordLearningEvent(db, {
      actorUid: "viewer", otherUid: "extra", type: "profileEngagement", key: "2026-09-01",
      strength: 0.1, weak: true, vector: HUMOR_HIGH, nowMs: NOW,
    });
    assert.equal(capped.outcome, "dailyCap");
    const nextDay = await recordLearningEvent(db, {
      actorUid: "viewer", otherUid: "extra", type: "profileEngagement", key: "2026-09-02",
      strength: 0.1, weak: true, vector: HUMOR_HIGH, nowMs: NOW + 86_400_000,
    });
    assert.equal(nextDay.outcome, "applied");
  });

  it("never throws into the core flow when personalization fails", async () => {
    const broken = {
      ...db,
      doc: () => {
        throw new Error("firestore down");
      },
    };
    assert.equal(
      await recordLearningEventSafely(broken, {actorUid: "a", otherUid: "b", type: "like", key: "k", strength: 1}),
      "failed",
    );
  });

  it("falls back to neutral ranking when the context cannot be loaded", async () => {
    const broken = {
      ...db,
      doc: () => ({get: async () => { throw new Error("unavailable"); }}),
    };
    const context = await loadPersonalizationContext(broken, "viewer");
    assert.equal(context.adjustments.humor, 1);
    assert.equal(context.enabled, false);
  });

  it("computes the pair vector from the canonical scorers, null where unmeasured", async () => {
    const scores = await pairScores(db, "viewer", "cand");
    assert.equal(scores.vector.relationship, 100);
    assert.equal(typeof scores.vector.interests, "number");
    assert.equal(typeof scores.vector.lifestyle, "number");
    assert.equal(scores.vector.values, null, "no relationship answers: not measured");
    assert.equal(scores.vector.music, null, "no Spotify: not measured");
    assert.equal(scores.vector.humor, null, "no humor calibration: not measured");
    assert.ok(scores.overall >= 0 && scores.overall <= 100);
  });
});

describe("event sources", () => {
  it("learns from a like written by the decision callables, once", async () => {
    const like = {fromUserId: "viewer", toUserId: "cand", action: "like"};
    await personalizationOnDecision.run(writeEvent(undefined, like, {likeId: "viewer_cand"}));
    const once = (await db.doc(personalizationProfilePath("viewer")).get()).data();
    assert.equal(once.eventCount, 1);
    // A retried trigger, and a rewrite with the same action, change nothing.
    await personalizationOnDecision.run(writeEvent(undefined, like, {likeId: "viewer_cand"}));
    await personalizationOnDecision.run(writeEvent(like, like, {likeId: "viewer_cand"}));
    const again = (await db.doc(personalizationProfilePath("viewer")).get()).data();
    assert.equal(again.eventCount, 1);
  });

  it("ignores unknown actions and malformed ids", async () => {
    await personalizationOnDecision.run(writeEvent(undefined, {fromUserId: "viewer", toUserId: "cand", action: "block"}));
    await personalizationOnDecision.run(writeEvent(undefined, {fromUserId: "viewer", toUserId: "viewer", action: "like"}));
    await personalizationOnDecision.run(writeEvent(undefined, {fromUserId: "a/b", toUserId: "cand", action: "like"}));
    assert.equal((await db.doc(personalizationProfilePath("viewer")).get()).exists, false);
  });

  it("learns from a match for both people", async () => {
    await personalizationOnMatchCreated.run({
      data: {data: () => ({userIds: ["cand", "viewer"], isActive: true})},
      params: {matchId: "cand_viewer"},
    });
    assert.equal((await db.doc(personalizationProfilePath("viewer")).get()).data().eventCount, 1);
    assert.equal((await db.doc(personalizationProfilePath("cand")).get()).data().eventCount, 1);
  });

  it("accepts weak engagement only from a signed-in member about someone else", async () => {
    await assert.rejects(callAs(recordProfileEngagement, null, {candidateUid: "cand"}), /sign-in/);
    await assert.rejects(callAs(recordProfileEngagement, "viewer", {candidateUid: "viewer"}), /invalid/);
    const idle = await callAs(recordProfileEngagement, "viewer", {candidateUid: "cand", dwellMs: 500});
    assert.equal(idle.outcome, "ignored");
    const first = await callAs(recordProfileEngagement, "viewer", {
      candidateUid: "cand", detailsOpened: true, dwellMs: 12_000,
    });
    assert.equal(first.outcome, "applied");
    const repeat = await callAs(recordProfileEngagement, "viewer", {
      candidateUid: "cand", detailsOpened: true, dwellMs: 12_000,
    });
    assert.equal(repeat.outcome, "duplicate", "one engagement per candidate per day");
  });

  it("serves the debug ranking view only inside the emulator", async () => {
    const previous = process.env.FUNCTIONS_EMULATOR;
    try {
      process.env.FUNCTIONS_EMULATOR = "false";
      await assert.rejects(callAs(debugPersonalizationRanking, "viewer", {}), /emulator-only/);
      process.env.FUNCTIONS_EMULATOR = "true";
      const view = await callAs(debugPersonalizationRanking, "viewer", {candidateUids: ["cand"]});
      assert.equal(view.enabled, true);
      assert.equal(view.active, false);
      assert.equal(view.candidates[0].explanation.personalPoints, 0);
    } finally {
      process.env.FUNCTIONS_EMULATOR = previous;
    }
  });
});
