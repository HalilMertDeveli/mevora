const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  ADJUSTMENT_BOUNDS,
  PERSONALIZATION_ALGORITHM_VERSION,
  PERSONALIZATION_DIMENSIONS,
  SIGNAL_STRENGTHS,
  WEAK_SIGNALS,
  LEARNING,
} = require("../lib/personalization/config.js");
const {
  applyLearningEvent,
  combineAdjustments,
  effectiveAdjustments,
  isObservedConfident,
  neutralAdjustments,
  neutralProfile,
  parseProfile,
  serializeProfile,
} = require("../lib/personalization/learner.js");
const {
  advanceConversationState,
  dwellStrength,
  emptyConversationState,
  engagementStrength,
  parseProfileEngagement,
  personalizationEventId,
} = require("../lib/personalization/signals.js");

const T0 = Date.UTC(2026, 8, 1, 12, 0, 0);
const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/** A candidate strong on humor and nothing else remarkable. */
const HUMOR_HIGH = {relationship: 50, values: 50, lifestyle: 50, interests: 50, music: 50, humor: 95};

function run(events, start = neutralProfile()) {
  let profile = start;
  events.forEach((event, i) => {
    profile = applyLearningEvent(profile, event, T0 + i * DAY).profile;
  });
  return profile;
}

function repeat(n, event) {
  return Array.from({length: n}, () => event);
}

function adj(profile, dimension) {
  return profile.dimensions[dimension].adjustment;
}

describe("personalization learner", () => {
  it("starts every dimension at exactly 1.00 for a new member", () => {
    const profile = neutralProfile();
    for (const d of PERSONALIZATION_DIMENSIONS) assert.equal(adj(profile, d), 1);
    assert.deepEqual(
      effectiveAdjustments(profile, true),
      Object.fromEntries(PERSONALIZATION_DIMENSIONS.map((d) => [d, 1])),
    );
  });

  it("moves only a tiny amount on a single like", () => {
    const profile = run([{type: "like", strength: SIGNAL_STRENGTHS.like, vector: HUMOR_HIGH}]);
    const change = adj(profile, "humor") - 1;
    assert.ok(change > 0, "a like of a humor-strong person is weak evidence humor matters");
    assert.ok(change <= 0.015, `one like moved humor by ${change}`);
  });

  it("keeps cold-start members close to neutral", () => {
    const profile = run(repeat(3, {type: "like", strength: SIGNAL_STRENGTHS.like, vector: HUMOR_HIGH}));
    assert.ok(Math.abs(adj(profile, "humor") - 1) < 0.04);
  });

  it("accumulates consistent evidence gradually and monotonically", () => {
    let profile = neutralProfile();
    const seen = [];
    for (let i = 0; i < 40; i++) {
      profile = applyLearningEvent(
        profile,
        {type: "conversationSurvived", strength: SIGNAL_STRENGTHS.conversationSurvived, vector: HUMOR_HIGH},
        T0 + i * DAY,
      ).profile;
      seen.push(adj(profile, "humor"));
    }
    for (let i = 1; i < seen.length; i++) assert.ok(seen[i] >= seen[i - 1]);
    for (let i = 1; i < seen.length; i++) assert.ok(seen[i] - seen[i - 1] <= 0.03 + 1e-9);
    assert.ok(seen.at(-1) > 1.15, `40 surviving conversations only reached ${seen.at(-1)}`);
  });

  it("never escapes 0.70-1.30 under extreme event volume", () => {
    const up = run(repeat(2000, {type: "secondSession", strength: 100, vector: HUMOR_HIGH}));
    const down = run(repeat(2000, {type: "unmatch", strength: -100, vector: HUMOR_HIGH}));
    for (const profile of [up, down]) {
      for (const d of PERSONALIZATION_DIMENSIONS) {
        assert.ok(adj(profile, d) >= ADJUSTMENT_BOUNDS.min && adj(profile, d) <= ADJUSTMENT_BOUNDS.max);
      }
    }
    assert.equal(adj(up, "humor"), ADJUSTMENT_BOUNDS.max);
    assert.equal(adj(down, "humor"), ADJUSTMENT_BOUNDS.min);
  });

  it("lets a surviving conversation count far more than the strongest profile engagement", () => {
    const strongest = engagementStrength({
      detailsOpened: true, photosViewed: 10, spotifyOpened: true, whyThisPersonOpened: true, dwellMs: 60_000,
    });
    const weak = run([{type: "profileEngagement", strength: strongest, vector: HUMOR_HIGH}]);
    const strong = run([{
      type: "conversationSurvived", strength: SIGNAL_STRENGTHS.conversationSurvived, vector: HUMOR_HIGH,
    }]);
    const weakMove = adj(weak, "humor") - 1;
    const strongMove = adj(strong, "humor") - 1;
    assert.ok(strongMove > 10 * weakMove, `strong ${strongMove} vs weak ${weakMove}`);
    assert.ok(weakMove < 0.003);
  });

  it("orders strong signals: like < match < started < survived < second session", () => {
    const order = ["like", "match", "conversationStarted", "conversationSurvived", "secondSession"];
    const moves = order.map((type) =>
      adj(run([{type, strength: SIGNAL_STRENGTHS[type], vector: HUMOR_HIGH}]), "humor") - 1,
    );
    for (let i = 1; i < moves.length; i++) assert.ok(moves[i] >= moves[i - 1], `${order[i]} < ${order[i - 1]}`);
    assert.ok(SIGNAL_STRENGTHS.superLike >= SIGNAL_STRENGTHS.like);
    assert.ok(SIGNAL_STRENGTHS.postMatchFeedbackPositive > SIGNAL_STRENGTHS.secondSession);
    assert.ok(Math.abs(SIGNAL_STRENGTHS.unmatch) < SIGNAL_STRENGTHS.conversationSurvived);
  });

  it("reverses learning on contradictory evidence without oscillating", () => {
    const positive = {type: "conversationSurvived", strength: SIGNAL_STRENGTHS.conversationSurvived, vector: HUMOR_HIGH};
    const negative = {type: "unmatch", strength: -SIGNAL_STRENGTHS.conversationSurvived, vector: HUMOR_HIGH};
    const raised = run(repeat(20, positive));
    const peak = adj(raised, "humor");
    let profile = raised;
    const path = [];
    for (let i = 0; i < 40; i++) {
      profile = applyLearningEvent(profile, negative, T0 + (100 + i) * DAY).profile;
      path.push(adj(profile, "humor"));
    }
    assert.ok(path[0] < peak);
    for (let i = 1; i < path.length; i++) assert.ok(path[i] <= path[i - 1] + 1e-9, "no bouncing back");
    assert.ok(path.at(-1) < 1, "enough contrary evidence turns it around");
  });

  it("treats a good outcome with someone LOW on a dimension as evidence it matters less", () => {
    const lowHumor = {...HUMOR_HIGH, humor: 10};
    const profile = run(repeat(10, {type: "conversationStarted", strength: 3, vector: lowHumor}));
    assert.ok(adj(profile, "humor") < 1);
  });

  it("learns only the dimensions the candidate actually stands out on", () => {
    const profile = run(repeat(10, {type: "match", strength: SIGNAL_STRENGTHS.match, vector: HUMOR_HIGH}));
    assert.ok(adj(profile, "humor") > 1);
    for (const d of PERSONALIZATION_DIMENSIONS.filter((x) => x !== "humor")) {
      assert.equal(adj(profile, d), 1, `${d} moved on humor-only evidence`);
    }
  });

  it("ignores unmeasured dimensions", () => {
    const profile = run(repeat(10, {
      type: "match", strength: 2, vector: {humor: null, music: undefined, values: 90},
    }));
    assert.equal(adj(profile, "humor"), 1);
    assert.equal(adj(profile, "music"), 1);
    assert.ok(adj(profile, "values") > 1);
  });

  it("applies nothing and learns nothing while personalization is OFF", () => {
    const learned = run(repeat(30, {type: "secondSession", strength: 4.5, vector: HUMOR_HIGH}));
    learned.partnerCount = LEARNING.minDistinctPartners;
    const off = effectiveAdjustments(learned, false);
    for (const d of PERSONALIZATION_DIMENSIONS) assert.equal(off[d], 1);
    const on = effectiveAdjustments(learned, true);
    assert.ok(on.humor > 1, "re-enabling restores the learned profile untouched");
  });

  it("gives the same result for the same inputs (deterministic)", () => {
    const events = [
      {type: "like", strength: 1, vector: HUMOR_HIGH},
      {type: "match", strength: 2, vector: {...HUMOR_HIGH, music: 90}},
      {type: "unmatch", strength: -2, vector: {...HUMOR_HIGH, values: 20}},
    ];
    assert.deepEqual(serializeProfile(run(events)), serializeProfile(run(events)));
  });

  it("fades old evidence with its half-life but keeps the adjustment until new events", () => {
    const learned = run(repeat(20, {type: "match", strength: 2, vector: HUMOR_HIGH}));
    const later = applyLearningEvent(
      learned,
      {type: "like", strength: 1, vector: {music: 90}},
      T0 + 260 * DAY,
    ).profile;
    assert.ok(later.dimensions.humor.evidence < learned.dimensions.humor.evidence / 3);
    assert.equal(later.dimensions.humor.adjustment, learned.dimensions.humor.adjustment);
  });

  it("reads missing, legacy, corrupt and future-version state as neutral", () => {
    for (const raw of [undefined, null, "x", {}, {algorithmVersion: 99, dimensions: {humor: {adjustment: 1.3}}}]) {
      const profile = parseProfile(raw);
      for (const d of PERSONALIZATION_DIMENSIONS) assert.equal(adj(profile, d), 1);
    }
    const tampered = parseProfile({
      algorithmVersion: PERSONALIZATION_ALGORITHM_VERSION,
      dimensions: {humor: {adjustment: 9, evidence: -4}, music: {adjustment: "NaN"}},
    });
    assert.equal(adj(tampered, "humor"), ADJUSTMENT_BOUNDS.max);
    assert.equal(tampered.dimensions.humor.evidence, 0);
    assert.equal(adj(tampered, "music"), 1);
  });

  it("round-trips through its stored form with the algorithm version", () => {
    const profile = run(repeat(5, {type: "match", strength: 2, vector: HUMOR_HIGH}));
    const stored = serializeProfile(profile);
    assert.equal(stored.algorithmVersion, PERSONALIZATION_ALGORITHM_VERSION);
    assert.deepEqual(serializeProfile(parseProfile(stored)), stored);
  });
});

describe("post-match quality outweighs swipe appeal", () => {
  it("gives more importance to the dimension behind lasting conversations", () => {
    // Music-strong people get liked a lot, but those conversations die.
    const musicHigh = {relationship: 50, values: 45, lifestyle: 50, interests: 55, music: 95, humor: 50};
    // Values-strong people get liked less, but talk continues for days.
    const valuesHigh = {relationship: 50, values: 95, lifestyle: 50, interests: 50, music: 45, humor: 50};
    const events = [];
    for (let i = 0; i < 12; i++) {
      events.push({type: "like", strength: SIGNAL_STRENGTHS.like, vector: musicHigh});
      if (i % 2 === 0) events.push({type: "match", strength: SIGNAL_STRENGTHS.match, vector: musicHigh});
      if (i % 4 === 0) events.push({type: "unmatch", strength: SIGNAL_STRENGTHS.unmatch, vector: musicHigh});
      if (i % 2 === 0) {
        events.push({type: "like", strength: SIGNAL_STRENGTHS.like, vector: valuesHigh});
        events.push({type: "match", strength: SIGNAL_STRENGTHS.match, vector: valuesHigh});
        events.push({type: "conversationStarted", strength: SIGNAL_STRENGTHS.conversationStarted, vector: valuesHigh});
        events.push({type: "conversationSurvived", strength: SIGNAL_STRENGTHS.conversationSurvived, vector: valuesHigh});
        events.push({type: "secondSession", strength: SIGNAL_STRENGTHS.secondSession, vector: valuesHigh});
      }
    }
    // Gradual: after the first quarter the gap is still small.
    const early = run(events.slice(0, Math.floor(events.length / 4)));
    const profile = run(events);
    assert.ok(adj(profile, "values") > adj(profile, "music"),
      `values ${adj(profile, "values")} vs music ${adj(profile, "music")}`);
    assert.ok(adj(early, "values") - adj(early, "music") < adj(profile, "values") - adj(profile, "music"));
    assert.ok(adj(profile, "values") <= ADJUSTMENT_BOUNDS.max);
  });
});

describe("conversation signals (metadata only)", () => {
  const users = ["a", "b"];
  function step(state, senderId, nowMs, messaged) {
    return advanceConversationState({state, userIds: users, messagedUserIds: messaged, senderId, nowMs});
  }

  it("starts only when both people have written, once", () => {
    let r = step(emptyConversationState(), "a", T0, ["a"]);
    assert.deepEqual(r.reached, []);
    r = step(r.state, "a", T0 + MIN, ["a"]);
    assert.deepEqual(r.reached, []);
    r = step(r.state, "b", T0 + 2 * MIN, ["a", "b"]);
    assert.deepEqual(r.reached, ["conversationStarted"]);
    r = step(r.state, "a", T0 + 3 * MIN, ["a", "b"]);
    assert.deepEqual(r.reached, []);
  });

  it("survives only with mutual activity 24h after the start", () => {
    let r = step(emptyConversationState(), "a", T0, ["a"]);
    r = step(r.state, "b", T0 + MIN, ["a", "b"]);
    r = step(r.state, "a", T0 + 25 * HOUR, ["a", "b"]);
    assert.ok(!r.reached.includes("conversationSurvived"), "one side alone is not survival");
    r = step(r.state, "b", T0 + 26 * HOUR, ["a", "b"]);
    assert.ok(r.reached.includes("conversationSurvived"));
  });

  it("counts a second session on a second distinct day of mutual activity", () => {
    let r = step(emptyConversationState(), "a", T0, ["a"]);
    r = step(r.state, "b", T0 + MIN, ["a", "b"]);
    r = step(r.state, "a", T0 + 2 * MIN, ["a", "b"]);
    assert.equal(r.state.mutualDays, 1);
    r = step(r.state, "a", T0 + 20 * HOUR, ["a", "b"]);
    const r2 = step(r.state, "b", T0 + 21 * HOUR, ["a", "b"]);
    assert.ok(r2.reached.includes("secondSession"));
  });

  it("does not double count a start that straddles midnight", () => {
    const beforeMidnight = Date.UTC(2026, 8, 1, 23, 59, 0);
    let r = step(emptyConversationState(), "a", beforeMidnight, ["a"]);
    r = step(r.state, "b", beforeMidnight + 2 * MIN, ["a", "b"]);
    assert.deepEqual(r.reached, ["conversationStarted"]);
    r = step(r.state, "a", beforeMidnight + 3 * MIN, ["a", "b"]);
    assert.equal(r.state.mutualDays, 1);
    assert.ok(!r.reached.includes("secondSession"));
  });

  it("reaches nothing new when the same message is replayed", () => {
    let r = step(emptyConversationState(), "a", T0, ["a"]);
    r = step(r.state, "b", T0 + MIN, ["a", "b"]);
    const replay = step(r.state, "b", T0 + MIN, ["a", "b"]);
    assert.deepEqual(replay.reached, []);
  });

  it("ignores a sender who is not a participant", () => {
    const r = advanceConversationState({
      state: emptyConversationState(), userIds: users, messagedUserIds: ["a", "b"], senderId: "x", nowMs: T0,
    });
    assert.deepEqual(r.reached, []);
  });
});

describe("weak engagement", () => {
  it("buckets and clamps dwell, and treats very long dwell as idle", () => {
    assert.equal(dwellStrength(0), 0);
    assert.equal(dwellStrength(2_000), 0);
    assert.ok(dwellStrength(5_000) > 0);
    assert.ok(dwellStrength(40_000) >= dwellStrength(15_000));
    assert.equal(dwellStrength(WEAK_SIGNALS.dwell.ignoreAboveMs + 1), 0);
    assert.equal(dwellStrength(Number.NaN), 0);
    assert.equal(dwellStrength(-50), 0);
  });

  it("caps one engagement event far below a like", () => {
    const max = engagementStrength(parseProfileEngagement({
      detailsOpened: true, photosViewed: 9999, spotifyOpened: true, whyThisPersonOpened: true, dwellMs: 60_000,
    }));
    assert.ok(max <= WEAK_SIGNALS.maxTotal);
    assert.ok(max < SIGNAL_STRENGTHS.like / 5);
  });

  it("accepts only booleans and bounded numbers from the client", () => {
    const parsed = parseProfileEngagement({
      detailsOpened: "yes", photosViewed: -3, spotifyOpened: 1, whyThisPersonOpened: true, dwellMs: "abc",
    });
    assert.deepEqual(parsed, {
      detailsOpened: false, photosViewed: 0, spotifyOpened: false, whyThisPersonOpened: true, dwellMs: 0,
    });
  });
});

describe("event identity", () => {
  it("is deterministic per occurrence and differs across keys and types", () => {
    const base = {type: "match", actorUid: "a", otherUid: "b", key: "a_b"};
    assert.equal(personalizationEventId(base), personalizationEventId({...base}));
    assert.notEqual(personalizationEventId(base), personalizationEventId({...base, key: "other"}));
    assert.notEqual(personalizationEventId(base), personalizationEventId({...base, type: "like"}));
    assert.notEqual(personalizationEventId(base), personalizationEventId({...base, actorUid: "b", otherUid: "a"}));
  });

  it("never stores the other person's uid in the id", () => {
    const id = personalizationEventId({type: "like", actorUid: "alice", otherUid: "bobUid123", key: "decision"});
    assert.ok(!id.includes("bobUid123"));
    assert.match(id, /^like_[0-9a-f]{32}$/);
  });
});

describe("privacy: personalization never touches message content", () => {
  it("has no reference to message text or ciphertext fields in its sources", () => {
    const dir = path.join(__dirname, "..", "src", "personalization");
    const forbidden = /\b(text|ciphertext|nonce|mac|lastMessage|previewText|messages\/)\b/;
    for (const file of fs.readdirSync(dir).filter((name) => name.endsWith(".ts"))) {
      const source = fs.readFileSync(path.join(dir, file), "utf8")
        // Comments may talk about text; code may not use it.
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\/\/.*$/gm, "");
      assert.doesNotMatch(source, forbidden, `${file} references message content`);
    }
  });

  it("derives conversation milestones from sender ids and timestamps alone", () => {
    const r = advanceConversationState({
      state: emptyConversationState(), userIds: ["a", "b"], messagedUserIds: ["a", "b"], senderId: "b", nowMs: T0,
    });
    assert.deepEqual(Object.keys(r.state).sort(), [
      "countedDay", "day", "daySenders", "lateSenders", "mutualDays",
      "secondSessionAtMs", "startedAtMs", "survivedAtMs",
    ]);
  });
});

describe("learning safeguards", () => {
  const survived = {type: "conversationSurvived", strength: SIGNAL_STRENGTHS.conversationSurvived, vector: HUMOR_HIGH};

  it("caps how far a dimension can move in one day, however many events land", () => {
    let profile = neutralProfile();
    for (let i = 0; i < 50; i++) {
      profile = applyLearningEvent(profile, survived, T0 + i * MIN).profile;
    }
    const moved = adj(profile, "humor") - 1;
    assert.ok(moved <= LEARNING.maxDailyMovePerDimension + 1e-9, `moved ${moved} in one day`);
    assert.ok(moved > 0);
    // The next day the budget is fresh again.
    const nextDay = applyLearningEvent(profile, survived, T0 + DAY).profile;
    assert.ok(adj(nextDay, "humor") > adj(profile, "humor"));
  });

  it("keeps the day budget per dimension and resets it on a new UTC day", () => {
    const first = applyLearningEvent(neutralProfile(), survived, T0).profile;
    assert.equal(first.dayKey, new Date(T0).toISOString().slice(0, 10));
    assert.ok(first.dayMovement.humor > 0);
    assert.equal(first.dayMovement.music, undefined);
    const later = applyLearningEvent(first, {...survived, vector: {music: 95}}, T0 + DAY).profile;
    assert.equal(later.dayMovement.humor, undefined, "yesterday's humor movement does not carry over");
    assert.ok(later.dayMovement.music > 0);
  });

  it("does not apply observed adjustments until enough different people stand behind them", () => {
    const learned = run(repeat(30, survived));
    assert.ok(adj(learned, "humor") > 1.05);
    for (let partners = 0; partners < LEARNING.minDistinctPartners; partners++) {
      learned.partnerCount = partners;
      assert.equal(isObservedConfident(learned), false);
      assert.deepEqual(effectiveAdjustments(learned, true), neutralAdjustments());
    }
    learned.partnerCount = LEARNING.minDistinctPartners;
    assert.equal(isObservedConfident(learned), true);
    assert.ok(effectiveAdjustments(learned, true).humor > 1.05);
  });

  it("round-trips partner count and day budget through the stored form", () => {
    const profile = applyLearningEvent(neutralProfile(), survived, T0).profile;
    profile.partnerCount = 2;
    const back = parseProfile(serializeProfile(profile));
    assert.equal(back.partnerCount, 2);
    assert.equal(back.dayKey, profile.dayKey);
    assert.ok(Math.abs(back.dayMovement.humor - profile.dayMovement.humor) < 1e-4);
  });

  it("combines declared and observed weights inside the band, neutral when both are", () => {
    const neutral = neutralAdjustments();
    assert.deepEqual(combineAdjustments(neutral, neutral), neutral);
    const declared = {...neutral, humor: 1.15, music: 0.88};
    const observed = {...neutral, humor: 1.3, music: 0.7};
    const combined = combineAdjustments(declared, observed);
    assert.equal(combined.humor, ADJUSTMENT_BOUNDS.max);
    assert.equal(combined.music, ADJUSTMENT_BOUNDS.min);
    assert.equal(combined.values, 1);
    const broken = combineAdjustments({...neutral, humor: NaN}, {...neutral, humor: Infinity});
    assert.equal(broken.humor, 1);
  });
});
