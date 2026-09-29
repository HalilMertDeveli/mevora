const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {composePicks, evaluatePool} = require("../lib/picks/selection.js");
const {PICK_COMPOSITION} = require("../lib/picks/config.js");
const {EXPLORATION, LEARNING, SIGNAL_STRENGTHS} = require("../lib/personalization/config.js");
const {
  applyLearningEvent,
  effectiveAdjustments,
  neutralAdjustments,
  neutralProfile,
} = require("../lib/personalization/learner.js");
const {
  explainPersonalRanking,
  personalRankingPoints,
  vectorFromSignals,
} = require("../lib/personalization/ranking.js");

const T0 = Date.UTC(2026, 8, 1, 12, 0, 0);

/** Same shape the Picks service builds; every dimension measured unless nulled. */
function signals(overrides = {}) {
  return {
    uid: "c",
    overall: 80,
    goalAligned: true,
    sharedGoal: "longTerm",
    questions: {score: 90, shared: 5, aligned: 4, topTopics: ["communication"]},
    lifestyle: 60,
    interests: {score: 50, sharedCount: 2},
    music: {score: 55, sharedArtistCount: 0, sharedTrackCount: 0, sharedGenreCount: 1},
    humor: {score: 60, sharedTraits: []},
    distanceKm: 5,
    disclosedDistanceKm: 5,
    withinPreferredRadius: true,
    isBoosted: false,
    ...overrides,
  };
}

const music = (score) => ({score, sharedArtistCount: 0, sharedTrackCount: 0, sharedGenreCount: 1});
const humor = (score) => ({score, sharedTraits: []});

/** Candidate A: humor-strong. Candidate B: music-strong. Otherwise identical. */
const A = signals({uid: "a", overall: 79, humor: humor(95), music: music(55)});
const B = signals({uid: "b", overall: 80, humor: humor(60), music: music(95)});

function learn(vector, type, times) {
  let profile = neutralProfile();
  for (let i = 0; i < times; i++) {
    profile = applyLearningEvent(
      profile,
      {type, strength: SIGNAL_STRENGTHS[type], vector},
      T0 + i * 86_400_000,
    ).profile;
  }
  // These outcomes stand for connections with several different people.
  profile.partnerCount = LEARNING.minDistinctPartners;
  return profile;
}

function compose(pool, adjustments, extra = {}) {
  return composePicks(evaluatePool(pool), {
    targetCount: extra.targetCount ?? 6,
    personalization: adjustments
      ? {viewerUid: "viewer", batchKey: extra.batchKey ?? "gen-1", adjustments}
      : undefined,
  });
}

const order = (picks) => picks.map((p) => p.candidateUid);

describe("personalized ranking inside Mevora Picks", () => {
  it("follows canonical compatibility while nothing is learned", () => {
    const withNeutral = compose([A, B], neutralAdjustments());
    const without = compose([A, B], null);
    assert.deepEqual(order(withNeutral), ["b", "a"]);
    assert.deepEqual(order(withNeutral), order(without));
    assert.ok(withNeutral.every((p) => p.selectionStrategy === "exploit"));
  });

  it("moves humor-strong candidates up after lasting conversations with humor-strong people", () => {
    const profile = learn(vectorFromSignals(A), "conversationSurvived", 25);
    const adjustments = effectiveAdjustments(profile, true);
    assert.ok(adjustments.humor > 1.05, `humor ${adjustments.humor}`);
    const picks = compose([A, B], adjustments);
    assert.equal(picks[0].candidateUid, "a");
  });

  it("does the same for music, the other way round", () => {
    const Bm = signals({uid: "b", overall: 79, humor: humor(60), music: music(95)});
    const Am = signals({uid: "a", overall: 80, humor: humor(95), music: music(55)});
    assert.deepEqual(order(compose([Am, Bm], neutralAdjustments())), ["a", "b"]);
    const adjustments = effectiveAdjustments(learn(vectorFromSignals(Bm), "secondSession", 25), true);
    assert.ok(adjustments.music > 1.05);
    assert.equal(compose([Am, Bm], adjustments)[0].candidateUid, "b");
  });

  it("ignores a learned level that is the same for every dimension (normalized weights)", () => {
    const uniform = Object.fromEntries(Object.keys(neutralAdjustments()).map((d) => [d, 1.2]));
    assert.deepEqual(order(compose([A, B], uniform)), order(compose([A, B], null)));
    assert.equal(personalRankingPoints(vectorFromSignals(A), uniform).points, 0);
    assert.ok(compose([A, B], uniform).every((p) => p.selectionStrategy === "exploit"));
  });

  it("falls back to non-adaptive ranking when the member switches personalization OFF", () => {
    const profile = learn(vectorFromSignals(A), "conversationSurvived", 25);
    const off = compose([A, B], effectiveAdjustments(profile, false));
    assert.deepEqual(order(off), order(compose([A, B], null)));
  });

  it("never lets a learned preference lift anyone past the quality floor", () => {
    const weak = signals({uid: "weak", overall: 50, humor: humor(100)});
    const adjustments = {...neutralAdjustments(), humor: 1.3};
    const picks = compose([A, B, weak], adjustments);
    assert.ok(!order(picks).includes("weak"));
  });

  it("keeps any single dimension from dominating (bounded points)", () => {
    const maxed = {...neutralAdjustments(), music: 1.3};
    const musicOnly = signals({uid: "m", overall: 70, music: music(100)});
    const {points, contributions} = personalRankingPoints(vectorFromSignals(musicOnly), maxed);
    const musicPoints = contributions.find((c) => c.dimension === "music").points;
    assert.ok(musicPoints <= 6, `music gave ${musicPoints} points`);
    assert.ok(points <= 10);
    // A strong-overall candidate with average music still beats a music-only one far below it.
    const holistic = signals({uid: "h", overall: 84, music: music(50)});
    assert.equal(compose([musicOnly, holistic], maxed)[0].candidateUid, "h");
  });

  it("does not hand one learned taste the whole batch", () => {
    const pool = [];
    for (let i = 0; i < 8; i++) {
      pool.push(signals({uid: `music${i}`, overall: 80, music: music(96), humor: null}));
    }
    for (let i = 0; i < 6; i++) {
      pool.push(signals({uid: `other${i}`, overall: 79, music: music(50), humor: humor(88)}));
    }
    const picks = compose(pool, {...neutralAdjustments(), music: 1.3});
    const musicPicks = picks.filter((p) => p.candidateUid.startsWith("music")).length;
    assert.ok(musicPicks < picks.length, "diversity survives a maxed preference");
    assert.ok(new Set(picks.map((p) => p.pickType)).size >= 2);
  });

  it("keeps Boost bounded and applied only in normal slots", () => {
    const boosted = signals({uid: "boosted", overall: 78, isBoosted: true});
    const boosted2 = signals({uid: "boosted2", overall: 78, isBoosted: true});
    const picks = compose([A, B, boosted, boosted2], neutralAdjustments());
    const boostedInBatch = picks.filter((p) => p.isBoosted);
    assert.ok(boostedInBatch.length <= 2);
    assert.ok(order(picks).indexOf("boosted") < order(picks).indexOf("boosted2"),
      `one boost bonus of ${PICK_COMPOSITION.boostBonus} per batch`);
  });

  it("explains a candidate's placement for debugging", () => {
    const adjustments = {...neutralAdjustments(), humor: 1.12, music: 0.94};
    const explanation = explainPersonalRanking(A.overall, vectorFromSignals(A), adjustments);
    assert.equal(explanation.baseOverall, 79);
    const humorPart = explanation.contributions.find((c) => c.dimension === "humor");
    assert.equal(humorPart.base, 95);
    assert.equal(humorPart.adjustment, 1.12);
    assert.ok(humorPart.points > 0);
    assert.equal(explanation.rankingScore, Math.round((79 + explanation.personalPoints) * 100) / 100);
  });
});

describe("exploration inside Mevora Picks", () => {
  /** 12 strong candidates; half match the learned humor taste, half do not. */
  function pool() {
    const out = [];
    for (let i = 0; i < 6; i++) {
      out.push(signals({uid: `fit${i}`, overall: 78 + (i % 3), humor: humor(92), music: music(50)}));
    }
    for (let i = 0; i < 6; i++) {
      out.push(signals({uid: `new${i}`, overall: 77 + (i % 3), humor: humor(40), music: music(80)}));
    }
    return out;
  }
  const learned = {...neutralAdjustments(), humor: 1.2};

  it("reserves a minority of slots once personalization is active", () => {
    const picks = compose(pool(), learned);
    const explore = picks.filter((p) => p.selectionStrategy === "explore");
    const exploit = picks.filter((p) => p.selectionStrategy === "exploit");
    assert.equal(picks.length, 6);
    assert.equal(explore.length, Math.max(EXPLORATION.minSlots, Math.round(6 * EXPLORATION.ratio)));
    assert.ok(exploit.length > explore.length, "exploitation stays the majority");
    assert.notEqual(picks[0].selectionStrategy, "explore", "the lead Pick is the best personal fit");
  });

  it("explores only strong candidates outside the learned pattern", () => {
    const byUid = new Map(pool().map((s) => [s.uid, s]));
    for (const key of ["gen-1", "gen-2", "gen-3", "gen-4"]) {
      for (const pick of compose(pool(), learned, {batchKey: key})) {
        if (pick.selectionStrategy !== "explore") continue;
        const s = byUid.get(pick.candidateUid);
        assert.ok(s.overall >= EXPLORATION.minOverall);
        assert.ok(personalRankingPoints(vectorFromSignals(s), learned).points <= 0);
      }
    }
  });

  it("is stable within a batch and rotates across batches", () => {
    const first = compose(pool(), learned, {batchKey: "gen-1"});
    const again = compose(pool(), learned, {batchKey: "gen-1"});
    assert.deepEqual(first, again, "reopening never reshuffles");
    const explored = new Set();
    for (let i = 0; i < 12; i++) {
      for (const pick of compose(pool(), learned, {batchKey: `gen-${i}`})) {
        if (pick.selectionStrategy === "explore") explored.add(pick.candidateUid);
      }
    }
    assert.ok(explored.size >= 2, `exploration never rotated: ${[...explored]}`);
  });

  it("does not explore while nothing is learned, or when personalization is OFF", () => {
    for (const adjustments of [neutralAdjustments(), effectiveAdjustments(neutralProfile(), false)]) {
      assert.ok(compose(pool(), adjustments).every((p) => p.selectionStrategy === "exploit"));
    }
  });

  it("keeps the slot normal rather than lowering the bar when nobody qualifies", () => {
    const onlyFits = pool().filter((s) => s.uid.startsWith("fit"));
    const weakOutsiders = [0, 1, 2].map((i) =>
      signals({uid: `weakNew${i}`, overall: EXPLORATION.minOverall - 3, humor: humor(40)}));
    const picks = compose([...onlyFits, ...weakOutsiders], learned);
    assert.ok(picks.every((p) => p.selectionStrategy === "exploit"));
    assert.ok(!picks.some((p) => p.candidateUid.startsWith("weakNew") && p.selectionStrategy === "explore"));
  });

  it("never reaches past the quality floor or the eligibility chain", () => {
    // composePicks only ever receives the canonical Discover pool; below the
    // quality floor nobody is eligible, exploration included.
    const belowFloor = [0, 1, 2].map((i) => signals({uid: `low${i}`, overall: 55, humor: humor(20)}));
    const picks = compose([...pool(), ...belowFloor], learned);
    assert.ok(!picks.some((p) => p.candidateUid.startsWith("low")));
  });
});
