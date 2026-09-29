const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

// The service binds getFirestore() at load, so the in-memory double goes first.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const {
  evaluateCandidate,
  qualifyBestOverall,
  qualifyHumorMatch,
  qualifyMusicMatch,
  qualifyNearbyMatch,
  qualifyUnexpectedMatch,
  qualifyValuesMatch,
  passesQualityFloor,
  primaryPickType,
  buildPickReasons,
  deepCompatibility,
  surfaceSimilarity,
} = require("../lib/picks/categories.js");
const {composePicks, evaluatePool} = require("../lib/picks/selection.js");
const lifecycle = require("../lib/picks/lifecycle.js");
const {PICKS_CONFIG, PICK_COMPOSITION} = require("../lib/picks/config.js");
const {pickConversationMilestones, CONVERSATION_SURVIVAL_MS} = require("../lib/picks/funnel.js");
const {
  attributePickMatch,
  recordPickDecision,
  scrubDeletedMemberFromPicks,
  servePicks,
  picksDocPath,
} = require("../lib/picks/service.js");
const {loadDiscoveryViewerContext} = require("../lib/discoveryPool.js");
const {getMevoraPicks} = require("../lib/picks/index.js");

/** A pair with nothing measured beyond the overall score. */
function signals(overrides = {}) {
  return {
    uid: "c",
    overall: 70,
    goalAligned: null,
    sharedGoal: null,
    questions: null,
    lifestyle: null,
    interests: null,
    music: null,
    humor: null,
    distanceKm: null,
    disclosedDistanceKm: null,
    withinPreferredRadius: true,
    isBoosted: false,
    ...overrides,
  };
}

const deepValues = {
  goalAligned: true,
  sharedGoal: "longTerm",
  questions: {score: 90, shared: 5, aligned: 4, topTopics: ["communication", "trust"]},
  lifestyle: 80,
};

describe("Pick categories", () => {
  it("high overall → Best Overall, absolutely or near the top of the pool", () => {
    assert.equal(qualifyBestOverall(signals({overall: 85}), 9), true);
    assert.equal(qualifyBestOverall(signals({overall: 72}), 0), true);
    assert.equal(qualifyBestOverall(signals({overall: 72}), 5), false);
    assert.equal(qualifyBestOverall(signals({overall: 65}), 0), false);
  });

  it("strong values and relationship views → Values Match", () => {
    assert.equal(qualifyValuesMatch(signals(deepValues)), true);
    // A shared goal alone is not a claim about values.
    assert.equal(qualifyValuesMatch(signals({goalAligned: true, lifestyle: 90})), false);
    assert.equal(
      qualifyValuesMatch(signals({...deepValues, questions: {...deepValues.questions, score: 40}})),
      false,
    );
  });

  it("strong humor compatibility → Humor Match; missing humor data never fabricates one", () => {
    assert.equal(qualifyHumorMatch(signals({humor: {score: 88, sharedTraits: ["absurd"]}})), true);
    assert.equal(qualifyHumorMatch(signals({humor: {score: 60, sharedTraits: []}})), false);
    assert.equal(qualifyHumorMatch(signals({humor: null})), false);
    const evaluation = evaluateCandidate(signals({overall: 80, goalAligned: true}), 0);
    assert.equal(evaluation.labels.includes("humorMatch"), false);
    const reasons = buildPickReasons(evaluation, "bestOverall");
    assert.equal(reasons.some((reason) => reason.type === "humor"), false);
  });

  it("strong music overlap → Music Match; missing music data never fabricates one", () => {
    const music = {score: 72, sharedArtistCount: 1, sharedTrackCount: 0, sharedGenreCount: 2};
    assert.equal(qualifyMusicMatch(signals({music})), true);
    assert.equal(qualifyMusicMatch(signals({music: {...music, score: 40, sharedArtistCount: 4}})), true);
    assert.equal(qualifyMusicMatch(signals({music: {...music, score: 40}})), false);
    assert.equal(qualifyMusicMatch(signals({music: null})), false);
    const reasons = buildPickReasons(evaluateCandidate(signals({overall: 80, goalAligned: true}), 0), "bestOverall");
    assert.equal(reasons.some((reason) => reason.type === "music"), false);
  });

  it("nearby + strong compatibility → Nearby Match; a weak nearby match never is", () => {
    assert.equal(qualifyNearbyMatch(signals({overall: 76, distanceKm: 3})), true);
    assert.equal(qualifyNearbyMatch(signals({overall: 64, distanceKm: 1})), false);
    assert.equal(qualifyNearbyMatch(signals({overall: 90, distanceKm: 40})), false);
    assert.equal(qualifyNearbyMatch(signals({overall: 90, distanceKm: null})), false);
    const weakNearby = evaluateCandidate(signals({overall: 64, goalAligned: true, distanceKm: 1}), 0);
    assert.equal(weakNearby.labels.includes("nearbyMatch"), false);
  });

  it("high deep compatibility + low surface similarity → Unexpected Match", () => {
    const unexpected = signals({
      ...deepValues,
      overall: 74,
      interests: {score: 15, sharedCount: 1},
    });
    assert.ok(deepCompatibility(unexpected).score >= 80);
    assert.ok(surfaceSimilarity(unexpected).score <= 40);
    assert.equal(qualifyUnexpectedMatch(unexpected), true);
  });

  it("Unexpected Match is never a low-overall or unmeasured candidate", () => {
    const base = {...deepValues, interests: {score: 15, sharedCount: 1}};
    assert.equal(qualifyUnexpectedMatch(signals({...base, overall: 60})), false);
    // Without measured interests nobody can say their interests differ.
    assert.equal(qualifyUnexpectedMatch(signals({...base, overall: 80, interests: null})), false);
    // Surface already similar: not unexpected, just a good match.
    assert.equal(
      qualifyUnexpectedMatch(signals({...base, overall: 80, interests: {score: 70, sharedCount: 5}})),
      false,
    );
    // One deep dimension is not enough to call it deep.
    assert.equal(
      qualifyUnexpectedMatch(
        signals({overall: 80, goalAligned: true, interests: {score: 10, sharedCount: 0}}),
      ),
      false,
    );
    const lowOverall = evaluateCandidate(signals({...base, overall: 55}), 0);
    assert.deepEqual(lowOverall.labels, []);
  });

  it("the quality floor needs positive evidence, not just the absence of red flags", () => {
    assert.equal(passesQualityFloor(signals({overall: 90})), false);
    assert.equal(passesQualityFloor(signals({overall: 90, goalAligned: true})), true);
    assert.equal(passesQualityFloor(signals({overall: 55, goalAligned: true})), false);
    assert.deepEqual(evaluateCandidate(signals({overall: 90}), 0).labels, []);
  });

  it("multiple labels resolve to one deterministic primary reason", () => {
    const multi = signals({
      overall: 86,
      goalAligned: true,
      humor: {score: 96, sharedTraits: ["dark", "absurd"]},
      music: {score: 74, sharedArtistCount: 2, sharedTrackCount: 0, sharedGenreCount: 1},
    });
    const first = evaluateCandidate(multi, 0);
    assert.deepEqual([...first.labels].sort(), ["bestOverall", "humorMatch", "musicMatch"]);
    // The specific, strong humor signal beats the generic overall one.
    assert.equal(primaryPickType(first), "humorMatch");
    for (let i = 0; i < 5; i++) {
      assert.equal(primaryPickType(evaluateCandidate(multi, 0)), "humorMatch");
    }
    const reasons = buildPickReasons(first, "humorMatch");
    assert.equal(reasons[0].type, "humor");
    assert.equal(reasons[0].score, 96);
    assert.deepEqual(reasons[0].meta.traits, ["dark", "absurd"]);
  });

  it("every percentage in a reason is a measured score", () => {
    const evaluation = evaluateCandidate(signals({...deepValues, overall: 80}), 0);
    for (const reason of buildPickReasons(evaluation, "valuesMatch")) {
      if (reason.type === "relationship" || reason.type === "communication") {
        assert.equal(reason.score, null, `${reason.type} has no score of its own`);
      }
    }
    const values = buildPickReasons(evaluation, "valuesMatch").find((r) => r.type === "values");
    assert.equal(values.score, 90);
  });
});

function strong(uid, overall, extra = {}) {
  return signals({uid, overall, goalAligned: true, sharedGoal: "longTerm", ...extra});
}

describe("Pick set composition", () => {
  it("6+ strong candidates → the target set of 6", () => {
    const pool = Array.from({length: 9}, (_, i) => strong(`u${i}`, 90 - i));
    const picks = composePicks(evaluatePool(pool), {targetCount: PICKS_CONFIG.targetCount});
    assert.equal(picks.length, 6);
    assert.deepEqual(picks.map((p) => p.rank), [0, 1, 2, 3, 4, 5]);
    assert.equal(new Set(picks.map((p) => p.candidateUid)).size, 6);
  });

  it("3 strong candidates → 3 Picks; quality is never lowered to reach 6", () => {
    const pool = [
      strong("a", 88),
      strong("b", 84),
      strong("c", 80),
      ...Array.from({length: 6}, (_, i) => strong(`weak${i}`, 50)),
      signals({uid: "noEvidence", overall: 90}),
    ];
    const picks = composePicks(evaluatePool(pool), {targetCount: 6});
    assert.deepEqual(picks.map((p) => p.candidateUid), ["a", "b", "c"]);
  });

  it("0 candidates → an empty set, not an error", () => {
    assert.deepEqual(composePicks(evaluatePool([]), {targetCount: 6}), []);
  });

  it("does not become 6 × Best Overall when real alternatives exist", () => {
    const pool = [
      ...Array.from({length: 8}, (_, i) => strong(`best${i}`, 92 - i)),
      strong("humor", 80, {humor: {score: 92, sharedTraits: ["dry"]}}),
      strong("music", 79, {
        music: {score: 85, sharedArtistCount: 4, sharedTrackCount: 1, sharedGenreCount: 2},
      }),
    ];
    const picks = composePicks(evaluatePool(pool), {targetCount: 6});
    const types = picks.map((p) => p.pickType);
    assert.ok(types.includes("humorMatch"), JSON.stringify(types));
    assert.ok(types.includes("musicMatch"), JSON.stringify(types));
    assert.ok(types.filter((t) => t === "bestOverall").length < 6);
    // The strongest candidate still leads.
    assert.equal(picks[0].candidateUid, "best0");
  });

  it("diversity is bounded: a much stronger candidate beats a diverse weaker one", () => {
    const pool = [
      strong("best0", 95),
      strong("best1", 94),
      strong("humorWeak", 66, {humor: {score: 80, sharedTraits: []}}),
    ];
    const picks = composePicks(evaluatePool(pool), {targetCount: 2});
    assert.deepEqual(picks.map((p) => p.candidateUid), ["best0", "best1"]);
  });

  it("is deterministic: the same pool always yields the same batch", () => {
    const pool = Array.from({length: 12}, (_, i) =>
      strong(`u${i}`, 70 + (i % 5), i % 3 === 0 ? {humor: {score: 80 + i, sharedTraits: []}} : {}),
    );
    const a = composePicks(evaluatePool(pool), {targetCount: 6});
    const b = composePicks(evaluatePool([...pool].reverse()), {targetCount: 6});
    assert.deepEqual(a, b);
  });

  it("Boost never lifts a candidate below the quality floor", () => {
    const pool = [strong("paid", 55, {isBoosted: true}), strong("good", 80)];
    const picks = composePicks(evaluatePool(pool), {targetCount: 6});
    assert.deepEqual(picks.map((p) => p.candidateUid), ["good"]);
  });

  it("Boost only breaks near-ties, and only once per batch", () => {
    const nearTie = composePicks(
      evaluatePool([strong("plain", 80), strong("paid", 78, {isBoosted: true})]),
      {targetCount: 2},
    );
    assert.equal(nearTie[0].candidateUid, "paid");
    const wideGap = composePicks(
      evaluatePool([strong("plain", 85), strong("paid", 75, {isBoosted: true})]),
      {targetCount: 2},
    );
    assert.equal(wideGap[0].candidateUid, "plain");
    assert.ok(PICK_COMPOSITION.boostBonus < 85 - 75);
    const many = composePicks(
      evaluatePool([
        strong("p1", 80, {isBoosted: true}),
        strong("p2", 80, {isBoosted: true}),
        strong("plain", 82),
      ]),
      {targetCount: 3},
    );
    // Only the first boosted pick carries the bonus; the second competes as-is.
    assert.deepEqual(many.map((p) => p.candidateUid), ["p1", "plain", "p2"]);
  });

  it("fills from inside the preferred radius before reaching beyond it", () => {
    const pool = [
      strong("far", 95, {withinPreferredRadius: false}),
      strong("near1", 80),
      strong("near2", 79),
    ];
    const two = composePicks(evaluatePool(pool), {targetCount: 2});
    assert.deepEqual(two.map((p) => p.candidateUid), ["near1", "near2"]);
    const three = composePicks(evaluatePool(pool), {targetCount: 3});
    assert.deepEqual(three.map((p) => p.candidateUid), ["near1", "near2", "far"]);
  });

  it("a top-up counts the Picks already live when balancing reasons", () => {
    const pool = [
      strong("best", 90),
      // 90 - one repeat penalty (5) = 85 < 86: the new reason wins the slot.
      strong("humor", 86, {humor: {score: 90, sharedTraits: []}}),
    ];
    const picks = composePicks(evaluatePool(pool), {
      targetCount: 2,
      existing: [{pickType: "bestOverall", isBoosted: false}],
      firstRank: 7,
    });
    assert.equal(picks.length, 1);
    assert.equal(picks[0].pickType, "humorMatch");
    assert.equal(picks[0].rank, 7);
  });
});

const DAY_MS = 86_400_000;

function storedBatch(nowMs, uids = ["a", "b", "c"]) {
  const composed = uids.map((uid, rank) => ({
    candidateUid: uid,
    rank,
    pickType: "bestOverall",
    labels: ["bestOverall"],
    reasons: [],
    overallScore: 80,
    isBoosted: false,
  }));
  return lifecycle.newBatch({
    generationId: "gen1",
    nowMs,
    picks: lifecycle.buildStoredPicks("gen1", composed, new Map(), nowMs),
    cooldowns: {},
  });
}

describe("Pick lifecycle", () => {
  const now = 1_700_000_000_000;

  it("Like removes the Pick, and deciding twice changes nothing", () => {
    const batch = storedBatch(now);
    const liked = lifecycle.applyDecision(batch, "a", "liked", now + 1);
    assert.equal(liked.changed, true);
    assert.deepEqual(lifecycle.activePicks(liked.batch).map((p) => p.candidateUid), ["b", "c"]);
    const again = lifecycle.applyDecision(liked.batch, "a", "passed", now + 2);
    assert.equal(again.changed, false);
    assert.equal(again.pick.state, "liked");
  });

  it("a like later confirmed as a match is upgraded", () => {
    const liked = lifecycle.applyDecision(storedBatch(now), "a", "liked", now).batch;
    const matched = lifecycle.applyDecision(liked, "a", "matched", now + 5);
    assert.equal(matched.changed, true);
    assert.equal(matched.pick.state, "matched");
    assert.equal(matched.pick.decidedAtMs, now);
  });

  it("Pass removes the Pick and it is never offered again in this batch", () => {
    const passed = lifecycle.applyDecision(storedBatch(now), "b", "passed", now).batch;
    assert.equal(lifecycle.activePicks(passed).some((p) => p.candidateUid === "b"), false);
    assert.ok(lifecycle.excludedFromSelection(passed, now).has("b"));
  });

  it("opening a profile without deciding keeps the Pick — there is no transition for it", () => {
    const batch = storedBatch(now);
    const roundTrip = lifecycle.parseBatch(JSON.parse(JSON.stringify(batch)));
    assert.deepEqual(lifecycle.activePicks(roundTrip).map((p) => p.candidateUid), ["a", "b", "c"]);
  });

  it("revalidation moves blocked, deleted and matched people out of the active set", () => {
    const outcomes = new Map([
      ["a", "ineligible"],
      ["b", "matched"],
      ["c", "active"],
    ]);
    const {batch, changed} = lifecycle.applyRevalidation(storedBatch(now), outcomes, now);
    assert.equal(changed, true);
    assert.deepEqual(lifecycle.activePicks(batch).map((p) => p.candidateUid), ["c"]);
  });

  it("an undecided Pick cools down when its batch expires; a decided one needs no cooldown", () => {
    const decided = lifecycle.applyDecision(storedBatch(now), "a", "liked", now).batch;
    const expiry = lifecycle.nextLogicalDayStartMs(now);
    assert.equal(lifecycle.isBatchLive(decided, expiry - 1), true);
    assert.equal(lifecycle.isBatchLive(decided, expiry), false);
    const cooldowns = lifecycle.cooldownsAfterExpiry(decided, expiry);
    assert.deepEqual(Object.keys(cooldowns).sort(), ["b", "c"]);
    assert.equal(cooldowns.b, expiry + PICKS_CONFIG.expiredCooldownMs);
    // Cooldowns lapse on their own.
    assert.deepEqual(lifecycle.liveCooldowns(cooldowns, expiry + PICKS_CONFIG.expiredCooldownMs), {});
  });

  it("recently passed or cooling-down people are excluded from the next selection", () => {
    const batch = {...storedBatch(now), cooldowns: {old: now + 1000, lapsed: now - 1}};
    const excluded = lifecycle.excludedFromSelection(batch, now);
    assert.ok(excluded.has("old"));
    assert.ok(excluded.has("a"));
    assert.equal(excluded.has("lapsed"), false);
  });

  it("tops up only with room, budget and after the scan interval", () => {
    const full = storedBatch(now, ["a", "b", "c", "d", "e", "f"]);
    assert.equal(lifecycle.needsTopUp(full, now + PICKS_CONFIG.topUpMinIntervalMs), false);
    // A Pick that stopped being eligible frees its slot...
    const blocked = lifecycle.applyRevalidation(full, new Map([["a", "ineligible"]]), now).batch;
    assert.equal(lifecycle.needsTopUp(blocked, now + 1), false);
    assert.equal(lifecycle.needsTopUp(blocked, now + PICKS_CONFIG.topUpMinIntervalMs), true);
    assert.equal(lifecycle.topUpSlots(blocked), 1);
    const exhausted = {...blocked, deliveredCount: PICKS_CONFIG.maxDeliveredPerBatch};
    assert.equal(lifecycle.needsTopUp(exhausted, now + PICKS_CONFIG.topUpMinIntervalMs), false);
  });

  it("never refills a slot spent on a like, a pass or a match", () => {
    let batch = storedBatch(now, ["a", "b", "c", "d", "e", "f"]);
    batch = lifecycle.applyDecision(batch, "a", "passed", now).batch;
    batch = lifecycle.applyDecision(batch, "b", "liked", now).batch;
    batch = lifecycle.applyDecision(batch, "c", "matched", now).batch;
    assert.equal(lifecycle.slotsUsed(batch), 6);
    assert.equal(lifecycle.needsTopUp(batch, now + PICKS_CONFIG.topUpMinIntervalMs), false);
    assert.equal(lifecycle.topUpSlots(batch), 0);
  });

  it("lives until the next logical day, whenever in the day it was made", () => {
    const offsetMs = PICKS_CONFIG.logicalDayUtcOffsetMinutes * 60_000;
    // 23:59 and 00:01 Istanbul time on the same calendar boundary.
    const lateEvening = Date.UTC(2026, 8, 29, 20, 59) ; // 23:59 at +03:00
    const justAfter = Date.UTC(2026, 8, 29, 21, 1); // 00:01 at +03:00, next day
    assert.equal(lifecycle.logicalDayKey(lateEvening), "2026-09-29");
    assert.equal(lifecycle.logicalDayKey(justAfter), "2026-09-30");
    assert.equal(lifecycle.nextLogicalDayStartMs(lateEvening), Date.UTC(2026, 8, 29, 21, 0));
    assert.equal(lifecycle.nextLogicalDayStartMs(justAfter), Date.UTC(2026, 8, 30, 21, 0));
    const made = storedBatch(lateEvening);
    assert.equal(made.refreshAtMs, Date.UTC(2026, 8, 29, 21, 0));
    assert.equal(lifecycle.isBatchLive(made, justAfter), false, "a new day brings a new set");
    const morning = storedBatch(Date.UTC(2026, 8, 30, 5, 0));
    assert.equal(lifecycle.isBatchLive(morning, Date.UTC(2026, 8, 30, 20, 59)), true, "same day stays");
    assert.ok(offsetMs > 0);
  });

  it("reads old or foreign documents as no batch rather than trusting them", () => {
    assert.equal(lifecycle.parseBatch(undefined), null);
    assert.equal(lifecycle.parseBatch({schemaVersion: 99, generationId: "x"}), null);
    assert.equal(lifecycle.parseBatch({schemaVersion: 1}), null);
  });

  it("scrubbing a deleted member removes every mention and the index entry", () => {
    const batch = {...storedBatch(now), cooldowns: {b: now + 5}};
    const scrubbed = lifecycle.scrubCandidate(batch, "b");
    assert.equal(scrubbed.picks.some((p) => p.candidateUid === "b"), false);
    assert.equal("b" in scrubbed.cooldowns, false);
    assert.equal(scrubbed.candidateUids.includes("b"), false);
    assert.equal(lifecycle.scrubCandidate(scrubbed, "b"), null);
  });

  it("the analytics pick id does not reveal the candidate", () => {
    const id = lifecycle.pickIdFor("gen1", "candidateUid123");
    assert.equal(id.includes("candidateUid123"), false);
    assert.equal(id, lifecycle.pickIdFor("gen1", "candidateUid123"));
    assert.notEqual(id, lifecycle.pickIdFor("gen2", "candidateUid123"));
  });
});

describe("Pick conversation milestones", () => {
  const match = (extra = {}) => ({
    userIds: ["a", "b"],
    introducedByPick: {a: {pickType: "humorMatch", generationId: "g"}},
    ...extra,
  });

  it("starts when both people have written, once", () => {
    assert.equal(pickConversationMilestones({match: match(), messagedUserIds: ["a"], nowMs: 10}).step, null);
    const started = pickConversationMilestones({match: match(), messagedUserIds: ["a", "b"], nowMs: 10});
    assert.equal(started.step, "conversationStarted");
    assert.deepEqual(started.pickTypes, ["humorMatch"]);
    assert.deepEqual(started.updates, {pickConversationStartedAt: 10});
  });

  it("survives when a message arrives 24h after it started, once", () => {
    const m = match({pickConversationStartedAt: 1000});
    assert.equal(
      pickConversationMilestones({match: m, messagedUserIds: ["a", "b"], nowMs: 1000 + CONVERSATION_SURVIVAL_MS - 1}).step,
      null,
    );
    assert.equal(
      pickConversationMilestones({match: m, messagedUserIds: ["a", "b"], nowMs: 1000 + CONVERSATION_SURVIVAL_MS}).step,
      "conversationSurvived24h",
    );
    const done = match({pickConversationStartedAt: 1000, pickConversationSurvived24hAt: 99});
    assert.equal(
      pickConversationMilestones({match: done, messagedUserIds: ["a", "b"], nowMs: 10 ** 12}).step,
      null,
    );
  });

  it("does nothing for a match that did not come from Picks", () => {
    const plain = {userIds: ["a", "b"]};
    assert.equal(pickConversationMilestones({match: plain, messagedUserIds: ["a", "b"], nowMs: 1}).step, null);
  });
});

// ---------------------------------------------------------------------------
// End to end against the in-memory Firestore: the real pool scan, the real
// eligibility chain, the real batch document.
// ---------------------------------------------------------------------------

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
    relationshipGoal: "longTerm",
    interests: ["hiking", "jazz", "cooking", "chess"],
    lifestyle: ["nonsmoker", "earlybird"],
    lastActiveAt: Timestamp.fromMillis(Date.now()),
    updatedAt: 1000,
    ...overrides,
  };
}

function seedWorld(candidates) {
  const seed = {
    [`users/${VIEWER}`]: {uid: VIEWER},
    [`profiles/${VIEWER}`]: profile(VIEWER, {gender: "woman", interestedIn: "men"}),
  };
  candidates.forEach(([uid, overrides], index) => {
    seed[`users/${uid}`] = {uid};
    seed[`profiles/${uid}`] = profile(uid, {updatedAt: 5000 - index, ...overrides});
  });
  db.reset(seed);
}

async function serve(nowMs) {
  const {viewer, boostSessions} = await loadDiscoveryViewerContext(db, VIEWER, {uid: VIEWER});
  return servePicks({db, viewer, boostSessions, nowMs});
}

describe("Mevora Picks service", () => {
  beforeEach(() => {
    seedWorld([
      ["c1", {}],
      ["c2", {}],
      ["c3", {}],
      ["c4", {}],
      ["c5", {}],
      ["c6", {}],
      ["c7", {}],
      ["c8", {}],
    ]);
  });

  it("serves a curated batch of 6 with real reasons, and the same batch on reopen", async () => {
    const first = await serve(Date.now());
    assert.equal(first.status, "ready");
    assert.equal(first.picks.length, 6);
    for (const item of first.picks) {
      assert.ok(item.pick.pickType, "every Pick has a type");
      assert.ok(item.pick.reasons.length > 0, "every Pick has a reason");
      assert.equal(item.uid === VIEWER, false);
      assert.equal("latitude" in item, false);
    }
    const again = await serve(Date.now());
    assert.equal(again.generationId, first.generationId);
    assert.deepEqual(again.picks.map((p) => p.uid), first.picks.map((p) => p.uid));
    assert.deepEqual(db.read("pickFunnelDaily/" + new Date().toISOString().slice(0, 10)).delivered, 6);
  });

  it("like and pass remove Picks; a passed person never comes back", async () => {
    const first = await serve(Date.now());
    const [liked, passed] = first.picks.map((p) => p.uid);
    await db.doc(`likes/${VIEWER}_${liked}`).set({fromUserId: VIEWER, toUserId: liked, action: "like"});
    await recordPickDecision({db, viewerUid: VIEWER, candidateUid: liked, decision: "liked"});
    await db.doc(`users/${VIEWER}/passedUsers/${passed}`).set({toUserId: passed});
    await recordPickDecision({db, viewerUid: VIEWER, candidateUid: passed, decision: "passed"});
    const after = await serve(Date.now());
    const uids = after.picks.map((p) => p.uid);
    assert.equal(uids.includes(liked), false);
    assert.equal(uids.includes(passed), false);
    // Even a brand-new batch a day later does not bring them back.
    const nextDay = await serve(Date.now() + DAY_MS + 1);
    assert.notEqual(nextDay.generationId, first.generationId);
    assert.equal(nextDay.picks.some((p) => p.uid === liked || p.uid === passed), false);
  });

  it("deciding does not buy more people: today's set stays finite", async () => {
    const first = await serve(Date.now());
    assert.equal(first.picks.length, 6);
    assert.equal(first.dayKey, lifecycle.logicalDayKey(Date.now()));
    for (const item of first.picks.slice(0, 3)) {
      await db.doc(`users/${VIEWER}/passedUsers/${item.uid}`).set({toUserId: item.uid});
      await recordPickDecision({db, viewerUid: VIEWER, candidateUid: item.uid, decision: "passed"});
    }
    // Well past the top-up interval, and two unused candidates remain in the pool.
    const later = await serve(Date.now() + PICKS_CONFIG.topUpMinIntervalMs + 1);
    assert.equal(later.generationId, first.generationId);
    assert.equal(later.picks.length, 3);
    assert.deepEqual(later.picks.map((p) => p.uid), first.picks.slice(3).map((p) => p.uid));
  });

  it("a Pick that stops being eligible is replaced from the same day's pool", async () => {
    const first = await serve(Date.now());
    const blocked = first.picks[0].uid;
    await db.doc(`blocks/${VIEWER}_${blocked}`).set({blockerId: VIEWER, blockedUserId: blocked});
    const later = await serve(Date.now() + PICKS_CONFIG.topUpMinIntervalMs + 1);
    assert.equal(later.generationId, first.generationId);
    assert.equal(later.picks.some((p) => p.uid === blocked), false);
    assert.equal(later.picks.length, 6);
  });

  it("a blocked or deleted member disappears on the next request", async () => {
    const first = await serve(Date.now());
    const [blocked, deleted] = first.picks.map((p) => p.uid);
    await db.doc(`blocks/${VIEWER}_${blocked}`).set({blockerId: VIEWER, blockedUserId: blocked});
    await db.doc(`profiles/${deleted}`).delete();
    const after = await serve(Date.now());
    const uids = after.picks.map((p) => p.uid);
    assert.equal(uids.includes(blocked), false);
    assert.equal(uids.includes(deleted), false);
  });

  it("a matched member does not reappear, and the match carries its Pick attribution", async () => {
    const first = await serve(Date.now());
    const partner = first.picks[0].uid;
    const matchId = [VIEWER, partner].sort().join("_");
    await db.doc(`matches/${matchId}`).set({userIds: [VIEWER, partner].sort(), isActive: true});
    await attributePickMatch({db, matchRef: db.doc(`matches/${matchId}`), uidA: VIEWER, uidB: partner});
    const match = db.read(`matches/${matchId}`);
    assert.equal(match.introducedByPick[VIEWER].pickType, first.picks[0].pick.pickType);
    assert.equal(match.introducedByPick[VIEWER].generationId, first.generationId);
    const stored = lifecycle.parseBatch(db.read(picksDocPath(VIEWER)));
    assert.equal(stored.picks.find((p) => p.candidateUid === partner).state, "matched");
    const after = await serve(Date.now());
    assert.equal(after.picks.some((p) => p.uid === partner), false);
    const day = db.read("pickFunnelDaily/" + new Date().toISOString().slice(0, 10));
    assert.equal(day.mutualMatch, 1);
  });

  it("3 strong candidates → 3 Picks, flagged as low supply", async () => {
    seedWorld([
      ["s1", {}],
      ["s2", {}],
      ["s3", {}],
      // Nothing in common beyond being active: below the floor.
      ["w1", {relationshipGoal: "casual", interests: ["x9"], lifestyle: ["smoker"]}],
      ["w2", {relationshipGoal: "casual", interests: ["x8"], lifestyle: ["nightowl"]}],
    ]);
    const result = await serve(Date.now());
    assert.deepEqual(result.picks.map((p) => p.uid).sort(), ["s1", "s2", "s3"]);
    assert.equal(result.status, "lowSupply");
  });

  it("0 candidates → an intentional empty state", async () => {
    seedWorld([]);
    const result = await serve(Date.now());
    assert.equal(result.status, "empty");
    assert.equal(result.emptyReason, "noCandidates");
    assert.deepEqual(result.picks, []);
  });

  it("once every Pick is decided, the empty state says so", async () => {
    seedWorld([["only", {}]]);
    const first = await serve(Date.now());
    assert.equal(first.picks.length, 1);
    await db.doc(`users/${VIEWER}/passedUsers/only`).set({toUserId: "only"});
    await recordPickDecision({db, viewerUid: VIEWER, candidateUid: "only", decision: "passed"});
    const after = await serve(Date.now());
    assert.equal(after.status, "empty");
    assert.equal(after.emptyReason, "allDecided");
  });

  it("undecided Picks rest after their batch expires instead of recycling", async () => {
    seedWorld([["a1", {}], ["a2", {}]]);
    const first = await serve(Date.now());
    assert.equal(first.picks.length, 2);
    const nextDay = await serve(Date.now() + DAY_MS + 1);
    assert.equal(nextDay.picks.length, 0);
    const later = await serve(
      Date.now() + DAY_MS * 2 + PICKS_CONFIG.expiredCooldownMs + 2,
    );
    assert.equal(later.picks.length, 2);
  });

  it("account deletion scrubs the member from other people's Picks", async () => {
    const first = await serve(Date.now());
    const gone = first.picks[0].uid;
    const scrubbed = await scrubDeletedMemberFromPicks(db, gone);
    assert.equal(scrubbed, 1);
    const stored = lifecycle.parseBatch(db.read(picksDocPath(VIEWER)));
    assert.equal(stored.candidateUids.includes(gone), false);
    assert.equal(stored.picks.some((p) => p.candidateUid === gone), false);
  });

  it("the callable refuses an unauthenticated caller and a suspended account", async () => {
    await assert.rejects(() => callAs(getMevoraPicks, null), (error) => error.code === "unauthenticated");
    await db.doc(`users/${VIEWER}`).set({uid: VIEWER, isSuspended: true});
    await assert.rejects(() => callAs(getMevoraPicks, VIEWER), (error) => error.code === "permission-denied");
  });

  it("the callable honours discovery being switched off", async () => {
    await db.doc(`userPreferences/${VIEWER}`).set({discoveryEnabled: false});
    const result = await callAs(getMevoraPicks, VIEWER);
    assert.equal(result.status, "empty");
    assert.deepEqual(result.picks, []);
  });

});
