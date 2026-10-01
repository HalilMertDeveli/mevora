/**
 * Humor Core progression — the pure scheduling rules.
 *
 * Fifteen first, then five per logical day, in one canonical order: no
 * run-ahead, no advance on missed days, a day's set frozen once touched,
 * media failures that never become evidence, retirement that keeps history,
 * and members from before the Core sequence carried over without loss.
 */
const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {HUMOR_CORE} = require("../lib/humor/coreSequence.js");
const schedule = require("../lib/humor/coreSchedule.js");
const {canonicalDayId, dailyResponseAgreement, shiftDayId} = require("../lib/humor/daily.js");

const {
  applyCoreMediaFailure,
  applyCoreRating,
  applyCoreReport,
  coreItemStatus,
  coreOnboardingProgress,
  coreRatedAnswers,
  coreSetProgress,
  defaultHumorCoreState,
  hasFinishedCoreOnboarding,
  isCoreSequenceExhausted,
  memberCoreSet,
  migrateLegacyHumorCoreState,
  parseHumorCoreState,
} = schedule;

const DAY1 = "2026-10-01";
const day = (n) => shiftDayId(DAY1, n - 1);
const T0 = Date.UTC(2026, 9, 1, 9, 0, 0);

/** v1 … vN, all live. */
function sequenceOf(count) {
  return Array.from({length: count}, (_, i) => ({id: `v${i + 1}`, active: true}));
}
const SEQ = sequenceOf(40);
const v = (from, to) => Array.from({length: to - from + 1}, (_, i) => `v${from + i}`);

/** Rate [ids] (default: everything open) of [dayId]'s set; fails on a refusal. */
function rate(state, dayId, ids, options = {}) {
  const sequence = options.sequence ?? SEQ;
  let next = state;
  const outcomes = [];
  const set = memberCoreSet(next, dayId, sequence, options.unavailable);
  for (const id of ids ?? set.contentIds) {
    const result = applyCoreRating({
      state: next,
      set: memberCoreSet(next, dayId, sequence, options.unavailable),
      id,
      rating: options.rating ?? "funny",
      nowMs: T0,
      sequence,
      unavailable: options.unavailable,
    });
    assert.equal(result.ok, true, `${id} on ${dayId}: ${result.reason}`);
    next = result.state;
    outcomes.push(result);
  }
  return {state: next, outcomes};
}

/** A member who finished V1–V15 on DAY1. */
function calibratedOnDay1(sequence = SEQ) {
  return rate(defaultHumorCoreState(), DAY1, undefined, {sequence}).state;
}

describe("initial calibration: V1–V15", () => {
  it("gives a fresh member V1–V15, in order", () => {
    const set = memberCoreSet(defaultHumorCoreState(), DAY1, SEQ);
    assert.equal(set.kind, "onboarding");
    assert.deepEqual(set.contentIds, v(1, 15));
    assert.equal(set.contentIds.length, HUMOR_CORE.onboardingCount);
  });

  it("gives every fresh member the same ids in the same order", () => {
    const a = memberCoreSet(defaultHumorCoreState(), DAY1, SEQ);
    const b = memberCoreSet(defaultHumorCoreState(), day(40), SEQ);
    assert.deepEqual(a.contentIds, b.contentIds);
  });

  it("resumes at V8 after seven ratings, with the set unchanged", () => {
    const {state} = rate(defaultHumorCoreState(), DAY1, v(1, 7));
    // What a restarted app, or a second device, computes from the stored state.
    const reloaded = parseHumorCoreState(JSON.parse(JSON.stringify(state)), SEQ);
    const set = memberCoreSet(reloaded, DAY1, SEQ);
    const progress = coreSetProgress(reloaded, set);
    assert.deepEqual(set.contentIds, v(1, 15));
    assert.equal(progress.nextIndex, 7);
    assert.equal(set.contentIds[progress.nextIndex], "v8");
    assert.equal(progress.answeredCount, 7);
    assert.deepEqual(coreOnboardingProgress(reloaded, SEQ), {
      completedCount: 7,
      totalCount: 15,
      complete: false,
    });
  });

  it("is complete only when every one of V1–V15 is rated", () => {
    const fourteen = rate(defaultHumorCoreState(), DAY1, v(1, 14));
    assert.equal(hasFinishedCoreOnboarding(fourteen.state, SEQ), false);
    assert.equal(fourteen.state.initialCompletedAtMs, null);
    assert.ok(fourteen.outcomes.every((o) => !o.onboardingCompletedNow));

    const last = rate(fourteen.state, DAY1, ["v15"]);
    assert.equal(last.outcomes[0].onboardingCompletedNow, true);
    assert.equal(last.outcomes[0].completedTodayNow, true);
    assert.equal(hasFinishedCoreOnboarding(last.state, SEQ), true);
    assert.equal(last.state.initialCompletedAtMs, T0);
  });

  it("can be finished across several days: tomorrow brings what is left, not a new fifteen", () => {
    const {state} = rate(defaultHumorCoreState(), DAY1, v(1, 6));
    const set = memberCoreSet(state, day(2), SEQ);
    assert.equal(set.kind, "onboarding");
    assert.deepEqual(set.contentIds, v(7, 15));
  });
});

describe("daily five", () => {
  it("does not unlock the daily five on the day the calibration is finished", () => {
    const state = calibratedOnDay1();
    const today = memberCoreSet(state, DAY1, SEQ);
    assert.equal(today.kind, "onboarding");
    assert.deepEqual(today.contentIds, v(1, 15));
    assert.equal(coreSetProgress(state, today).completed, true);
    for (const id of v(16, 20)) {
      assert.deepEqual(
        applyCoreRating({state, set: today, id, rating: "funny", nowMs: T0, sequence: SEQ}),
        {ok: false, reason: "not-in-set"},
      );
    }
  });

  it("gives V16–V20 on the next logical day", () => {
    const set = memberCoreSet(calibratedOnDay1(), day(2), SEQ);
    assert.equal(set.kind, "core");
    assert.deepEqual(set.contentIds, v(16, 20));
    assert.equal(set.contentIds.length, HUMOR_CORE.dailyCount);
  });

  it("does not slide V21 into today when V16 is rated", () => {
    const {state} = rate(calibratedOnDay1(), day(2), ["v16"]);
    const set = memberCoreSet(state, day(2), SEQ);
    assert.deepEqual(set.contentIds, v(16, 20));
    assert.ok(!set.contentIds.includes("v21"));
    const progress = coreSetProgress(state, set);
    assert.deepEqual(
      set.contentIds.filter((_, i) => progress.statuses[i] === "open"),
      v(17, 20),
    );
  });

  it("keeps today's set and its id frozen through every rating", () => {
    let state = calibratedOnDay1();
    const first = memberCoreSet(state, day(2), SEQ);
    for (const id of v(16, 20)) {
      state = rate(state, day(2), [id]).state;
      const now = memberCoreSet(state, day(2), SEQ);
      assert.deepEqual(now.contentIds, first.contentIds);
      assert.equal(state.today.setId, first.setId);
    }
    assert.deepEqual(state.today.contentIds, v(16, 20));
  });

  it("offers nothing more once today's five are done", () => {
    const {state, outcomes} = rate(calibratedOnDay1(), day(2));
    assert.equal(outcomes.at(-1).completedTodayNow, true);
    const set = memberCoreSet(state, day(2), SEQ);
    assert.deepEqual(set.contentIds, v(16, 20));
    assert.equal(coreSetProgress(state, set).completed, true);
    assert.equal(
      applyCoreRating({state, set, id: "v21", rating: "funny", nowMs: T0, sequence: SEQ}).ok,
      false,
    );
  });

  it("gives V21–V25 the day after", () => {
    const {state} = rate(calibratedOnDay1(), day(2));
    assert.deepEqual(memberCoreSet(state, day(3), SEQ).contentIds, v(21, 25));
  });

  it("does not advance on missed days: back after three days means V21–V25", () => {
    const {state} = rate(calibratedOnDay1(), day(2));
    assert.deepEqual(memberCoreSet(state, day(6), SEQ).contentIds, v(21, 25));
    assert.deepEqual(memberCoreSet(state, day(400), SEQ).contentIds, v(21, 25));
  });

  it("carries an unfinished day over: two of five today, the other three lead tomorrow", () => {
    const {state} = rate(calibratedOnDay1(), day(2), v(16, 17));
    assert.deepEqual(memberCoreSet(state, day(3), SEQ).contentIds, [...v(18, 20), "v21", "v22"]);
  });

  it("counts a completed day once", () => {
    let state = rate(calibratedOnDay1(), day(2)).state;
    assert.equal(state.completedDays, 2);
    const again = rate(state, day(2), ["v16"], {rating: "neutral"});
    assert.equal(again.outcomes[0].completedTodayNow, false);
    assert.equal(again.state.completedDays, 2);
    state = rate(again.state, day(3)).state;
    assert.equal(state.completedDays, 3);
  });

  it("ends when the sequence does: nothing is invented past the last entry", () => {
    const short = sequenceOf(17);
    let state = calibratedOnDay1(short);
    assert.deepEqual(memberCoreSet(state, day(2), short).contentIds, ["v16", "v17"]);
    state = rate(state, day(2), undefined, {sequence: short}).state;
    assert.equal(isCoreSequenceExhausted(state, short), true);
    assert.deepEqual(memberCoreSet(state, day(3), short).contentIds, []);
  });
});

describe("server authority", () => {
  it("refuses tomorrow's entries today", () => {
    const state = calibratedOnDay1();
    const set = memberCoreSet(state, day(2), SEQ);
    for (const id of v(21, 25)) {
      assert.deepEqual(
        applyCoreRating({state, set, id, rating: "funny", nowMs: T0, sequence: SEQ}),
        {ok: false, reason: "not-in-set"},
      );
    }
  });

  it("refuses an earlier entry and any id the client makes up", () => {
    const state = rate(calibratedOnDay1(), day(2)).state;
    const set = memberCoreSet(state, day(3), SEQ);
    for (const id of ["v1", "v16", "v40", "hc_gif_anything", "", "../users/x"]) {
      assert.equal(
        applyCoreRating({state, set, id, rating: "funny", nowMs: T0, sequence: SEQ}).ok,
        false,
        id,
      );
    }
  });

  it("has no clock of its own: the day is always the server's argument", () => {
    const source = fs.readFileSync(
      path.join(__dirname, "..", "src", "humor", "coreSchedule.ts"),
      "utf8",
    );
    assert.ok(!/Date\.now\(|new Date\(/.test(source), "coreSchedule.ts must not read a clock");
  });

  it("uses the same UTC+3 boundary as Picks and the relationship questions", () => {
    const {logicalDayKey} = require("../lib/picks/lifecycle.js");
    const {learningDayKey} = require("../lib/relationshipLearning/schedule.js");
    for (let hour = 0; hour < 72; hour += 1) {
      const at = Date.UTC(2026, 9, 1, 0, 0, 0) + hour * 3_600_000 + 59 * 60_000;
      assert.equal(canonicalDayId(at), logicalDayKey(at), `picks @ +${hour}h`);
      assert.equal(canonicalDayId(at), learningDayKey(at), `learning @ +${hour}h`);
    }
  });
});

describe("idempotency", () => {
  it("changes nothing when the same rating arrives again", () => {
    const first = rate(calibratedOnDay1(), day(2), ["v16"], {rating: "very_funny"});
    const set = memberCoreSet(first.state, day(2), SEQ);
    const again = applyCoreRating({
      state: first.state,
      set,
      id: "v16",
      rating: "very_funny",
      nowMs: T0 + 5000,
      sequence: SEQ,
    });
    assert.equal(again.ok, true);
    assert.equal(again.changed, false);
    assert.equal(again.state, first.state);
  });

  it("replaces a rating of today's entry instead of adding one", () => {
    const first = rate(calibratedOnDay1(), day(2), ["v16"], {rating: "very_funny"});
    const second = rate(first.state, day(2), ["v16"], {rating: "not_funny"});
    assert.equal(second.outcomes[0].changed, true);
    assert.equal(second.state.answers.v16.rating, "not_funny");
    assert.equal(Object.keys(second.state.answers).length, 16);
    assert.equal(coreSetProgress(second.state, memberCoreSet(second.state, day(2), SEQ)).answeredCount, 1);
  });
});

describe("media failure", () => {
  const fail = (state, dayId, id, sequence = SEQ) =>
    applyCoreMediaFailure({
      state,
      set: memberCoreSet(state, dayId, sequence),
      id,
      nowMs: T0,
      sequence,
    });

  it("is never evidence: no rating is stored", () => {
    const result = fail(calibratedOnDay1(), day(2), "v16");
    assert.equal(result.ok, true);
    assert.equal(result.changed, true);
    assert.equal(result.state.answers.v16, undefined);
    assert.equal(coreRatedAnswers(result.state).has("v16"), false);
    assert.equal(coreItemStatus(result.state, "v16", day(2)), "deferred");
  });

  it("lets the day finish and brings the entry back first the next day", () => {
    let state = fail(calibratedOnDay1(), day(2), "v16").state;
    const rest = rate(state, day(2), v(17, 20));
    assert.equal(rest.outcomes.at(-1).completedTodayNow, true);
    state = rest.state;
    assert.deepEqual(memberCoreSet(state, day(2), SEQ).contentIds, v(16, 20));
    assert.deepEqual(memberCoreSet(state, day(3), SEQ).contentIds, ["v16", ...v(21, 24)]);
  });

  it("never substitutes other content for the failed entry", () => {
    const state = fail(calibratedOnDay1(), day(2), "v16").state;
    assert.deepEqual(memberCoreSet(state, day(2), SEQ).contentIds, v(16, 20));
  });

  it("waives the entry for the member after it failed on a second day", () => {
    let state = fail(calibratedOnDay1(), day(2), "v16").state;
    assert.equal(state.waived.v16, undefined);
    const second = fail(state, day(3), "v16");
    state = second.state;
    assert.equal(state.waived.v16.reason, "media_failed");
    assert.equal(state.answers.v16, undefined);
    assert.equal(coreItemStatus(state, "v16", day(3)), "waived");
    assert.ok(!memberCoreSet(state, day(4), SEQ).contentIds.includes("v16"));
  });

  it("counts a repeat on the same day once", () => {
    const first = fail(calibratedOnDay1(), day(2), "v16");
    const repeat = fail(first.state, day(2), "v16");
    assert.equal(repeat.changed, false);
    assert.deepEqual(repeat.state.mediaFailures.v16.days, [day(2)]);
  });

  it("never overrides a rating", () => {
    const rated = rate(calibratedOnDay1(), day(2), ["v16"], {rating: "funny"}).state;
    const result = fail(rated, day(2), "v16");
    assert.equal(result.changed, false);
    assert.equal(result.state.answers.v16.rating, "funny");
  });

  it("is refused for an entry outside today's set", () => {
    assert.deepEqual(fail(calibratedOnDay1(), day(2), "v21"), {ok: false, reason: "not-in-set"});
  });

  it("pauses the initial calibration instead of faking a rating", () => {
    let state = fail(defaultHumorCoreState(), DAY1, "v7").state;
    const rest = rate(state, DAY1, [...v(1, 6), ...v(8, 15)]);
    state = rest.state;
    assert.equal(rest.outcomes.at(-1).completedTodayNow, true);
    assert.equal(rest.outcomes.at(-1).onboardingCompletedNow, false);
    assert.equal(hasFinishedCoreOnboarding(state, SEQ), false);
    assert.deepEqual(coreOnboardingProgress(state, SEQ), {
      completedCount: 14,
      totalCount: 15,
      complete: false,
    });

    // Tomorrow: only the one that is left — and the daily five still wait a day.
    const tomorrow = memberCoreSet(state, day(2), SEQ);
    assert.equal(tomorrow.kind, "onboarding");
    assert.deepEqual(tomorrow.contentIds, ["v7"]);
    const done = rate(state, day(2), ["v7"]);
    assert.equal(done.outcomes[0].onboardingCompletedNow, true);
    assert.equal(memberCoreSet(done.state, day(2), SEQ).kind, "onboarding");
    assert.deepEqual(memberCoreSet(done.state, day(3), SEQ).contentIds, v(16, 20));
  });

  it("cannot hold the initial calibration forever: a second failed day finishes it", () => {
    let state = fail(defaultHumorCoreState(), DAY1, "v7").state;
    state = rate(state, DAY1, [...v(1, 6), ...v(8, 15)]).state;
    const second = fail(state, day(2), "v7");
    assert.equal(second.onboardingCompletedNow, true);
    assert.equal(hasFinishedCoreOnboarding(second.state, SEQ), true);
    assert.equal(Object.keys(second.state.answers).length, 14);
  });
});

describe("reports", () => {
  it("waives a reported entry of today's set, without a rating", () => {
    const state = calibratedOnDay1();
    const result = applyCoreReport({
      state,
      set: memberCoreSet(state, day(2), SEQ),
      id: "v16",
      nowMs: T0,
      sequence: SEQ,
    });
    assert.equal(result.changed, true);
    assert.equal(result.state.waived.v16.reason, "reported");
    assert.equal(result.state.answers.v16, undefined);
    assert.deepEqual(result.state.today.contentIds, v(16, 20));
  });

  it("leaves a rating alone, and ignores an entry that is not in front of the member", () => {
    const rated = rate(calibratedOnDay1(), day(2), ["v16"]).state;
    const set = memberCoreSet(rated, day(2), SEQ);
    const onRated = applyCoreReport({state: rated, set, id: "v16", nowMs: T0, sequence: SEQ});
    assert.equal(onRated.changed, false);
    const outside = applyCoreReport({state: rated, set, id: "v30", nowMs: T0, sequence: SEQ});
    assert.equal(outside.changed, false);
    assert.equal(outside.state.waived.v30, undefined);
  });
});

describe("retirement and versions", () => {
  const retire = (sequence, id, reason = "clip removed by provider") =>
    sequence.map((entry) => (entry.id === id ? {...entry, active: false, retiredReason: reason} : entry));

  it("skips a retired entry without backfilling: a retired V9 makes the calibration fourteen", () => {
    const sequence = retire(SEQ, "v9");
    const set = memberCoreSet(defaultHumorCoreState(), DAY1, sequence);
    assert.deepEqual(set.contentIds, [...v(1, 8), ...v(10, 15)]);
    assert.equal(coreOnboardingProgress(defaultHumorCoreState(), sequence).totalCount, 14);
    const state = rate(defaultHumorCoreState(), DAY1, undefined, {sequence}).state;
    assert.equal(hasFinishedCoreOnboarding(state, sequence), true);
    assert.deepEqual(memberCoreSet(state, day(2), sequence).contentIds, v(16, 20));
  });

  it("keeps positions: retiring V18 does not move V19 or V20", () => {
    const sequence = retire(SEQ, "v18");
    const set = memberCoreSet(calibratedOnDay1(sequence), day(2), sequence);
    assert.deepEqual(set.contentIds, ["v16", "v17", "v19", "v20", "v21"]);
  });

  it("keeps a rating of an entry that was retired afterwards", () => {
    const state = rate(calibratedOnDay1(), day(2), ["v16"], {rating: "very_funny"}).state;
    const sequence = retire(SEQ, "v16");
    const reloaded = parseHumorCoreState(JSON.parse(JSON.stringify(state)), sequence);
    assert.equal(reloaded.answers.v16.rating, "very_funny");
    assert.equal(coreRatedAnswers(reloaded).get("v16"), "very_funny");
    // The frozen day drops the retired entry; nothing replaces it.
    assert.deepEqual(memberCoreSet(reloaded, day(2), sequence).contentIds, v(17, 20));
  });

  it("asks a versioned successor as its own entry, at the end", () => {
    const sequence = [
      ...retire(sequenceOf(20), "v3"),
      {id: "v3_v2", active: true, supersedes: "v3"},
    ];
    // Rated the old version: the successor is still a new measurement.
    let state = rate(defaultHumorCoreState(), DAY1, undefined, {sequence: sequenceOf(20)}).state;
    state = parseHumorCoreState(JSON.parse(JSON.stringify(state)), sequence);
    assert.equal(state.answers.v3.rating, "funny");
    state = rate(state, day(2), undefined, {sequence}).state;
    assert.deepEqual(memberCoreSet(state, day(3), sequence).contentIds, ["v3_v2"]);
    assert.notEqual(state.answers.v3, state.answers.v3_v2);
  });

  it("treats content that was taken down like a retired entry — skipped, never swapped", () => {
    const unavailable = new Set(["v17"]);
    const state = calibratedOnDay1();
    assert.deepEqual(memberCoreSet(state, day(2), SEQ, unavailable).contentIds, [
      "v16",
      "v18",
      "v19",
      "v20",
      "v21",
    ]);
    // Taken down after the day was frozen: the set shrinks instead.
    const frozen = rate(state, day(2), ["v16"]).state;
    assert.deepEqual(memberCoreSet(frozen, day(2), SEQ, unavailable).contentIds, [
      "v16",
      "v18",
      "v19",
      "v20",
    ]);
  });

  it("does not call an empty catalogue a finished calibration", () => {
    const everything = new Set(SEQ.map((entry) => entry.id));
    const state = defaultHumorCoreState();
    assert.equal(hasFinishedCoreOnboarding(state, SEQ, everything), false);
    assert.deepEqual(memberCoreSet(state, DAY1, SEQ, everything).contentIds, []);
    assert.deepEqual(coreOnboardingProgress(state, SEQ, everything), {
      completedCount: 0,
      totalCount: 0,
      complete: false,
    });
  });
});

describe("members from before the Core sequence", () => {
  const migrate = (overrides = {}) =>
    migrateLegacyHumorCoreState({
      sequence: SEQ,
      interactions: new Map(),
      legacyReady: false,
      legacyCompletedCount: 0,
      legacyCompletedAtMs: null,
      legacyDailyTouchedToday: false,
      todayId: DAY1,
      dayIdOf: canonicalDayId,
      nowMs: T0,
      ...overrides,
    });

  it("starts a member with no history at V1–V15", () => {
    const state = migrate();
    assert.equal(state.migration.from, "none");
    assert.deepEqual(memberCoreSet(state, DAY1, SEQ).contentIds, v(1, 15));
  });

  it("does not make a calibrated member redo fifteen: five a day, from V1", () => {
    const state = migrate({
      legacyReady: true,
      legacyCompletedCount: 15,
      legacyCompletedAtMs: T0 - 5 * 86_400_000,
    });
    assert.equal(hasFinishedCoreOnboarding(state, SEQ), true);
    const set = memberCoreSet(state, DAY1, SEQ);
    assert.equal(set.kind, "core");
    assert.deepEqual(set.contentIds, v(1, 5));
    assert.deepEqual(coreOnboardingProgress(state, SEQ), {
      completedCount: 15,
      totalCount: 15,
      complete: true,
    });
    assert.deepEqual(state.migration, {
      from: "adaptive-v1",
      legacyComplete: true,
      legacyCompletedCount: 15,
      importedRatings: 0,
      importedWaivers: 0,
      atMs: T0,
    });
  });

  it("counts a Core entry they already rated, and does not ask it again", () => {
    const state = migrate({
      legacyReady: true,
      legacyCompletedCount: 15,
      legacyCompletedAtMs: T0 - 5 * 86_400_000,
      interactions: new Map([
        ["v2", {rating: "very_funny"}],
        ["v4", {rating: "not_funny"}],
        ["v30", {rating: "funny"}],
      ]),
    });
    assert.equal(state.migration.importedRatings, 3);
    assert.deepEqual(state.answers.v2, {
      rating: "very_funny",
      dayId: null,
      answeredAtMs: 0,
      source: "legacy",
    });
    assert.deepEqual(memberCoreSet(state, DAY1, SEQ).contentIds, ["v1", "v3", "v5", "v6", "v7"]);
  });

  it("still asks an entry they only skipped, and waives one they reported", () => {
    const state = migrate({
      legacyReady: true,
      legacyCompletedAtMs: T0 - 5 * 86_400_000,
      interactions: new Map([
        ["v1", {rating: null, skipped: true, skipReason: "user"}],
        ["v2", {rating: null, skipped: true, reported: true}],
        ["v3", {rating: "bogus"}],
      ]),
    });
    assert.equal(state.answers.v1, undefined);
    assert.equal(state.waived.v2.reason, "reported");
    assert.equal(state.answers.v3, undefined);
    assert.deepEqual(memberCoreSet(state, DAY1, SEQ).contentIds, ["v1", "v3", "v4", "v5", "v6"]);
  });

  it("lets a member in the middle of the old calibration continue with what is left of V1–V15", () => {
    const state = migrate({
      legacyCompletedCount: 9,
      interactions: new Map(v(1, 4).map((id) => [id, {rating: "funny"}])),
    });
    assert.equal(state.migration.from, "adaptive-v1");
    assert.equal(state.migration.legacyComplete, false);
    const set = memberCoreSet(state, DAY1, SEQ);
    assert.equal(set.kind, "onboarding");
    assert.deepEqual(set.contentIds, v(5, 15));
    assert.deepEqual(coreOnboardingProgress(state, SEQ), {
      completedCount: 4,
      totalCount: 15,
      complete: false,
    });
  });

  it("starts tomorrow for a member who finished the old calibration today", () => {
    const state = migrate({legacyReady: true, legacyCompletedCount: 15, legacyCompletedAtMs: T0 - 60_000});
    const today = memberCoreSet(state, DAY1, SEQ);
    assert.equal(today.kind, "onboarding");
    assert.deepEqual(today.contentIds, []);
    assert.equal(coreSetProgress(state, today).completed, true);
    assert.deepEqual(memberCoreSet(state, day(2), SEQ).contentIds, v(1, 5));
  });

  it("starts tomorrow for a member who already did the old daily set today", () => {
    const state = migrate({
      legacyReady: true,
      legacyCompletedAtMs: T0 - 9 * 86_400_000,
      legacyDailyTouchedToday: true,
    });
    assert.deepEqual(memberCoreSet(state, DAY1, SEQ).contentIds, []);
    assert.equal(state.today.kind, "core");
    assert.deepEqual(memberCoreSet(state, day(2), SEQ).contentIds, v(1, 5));
  });

  it("admits a ready profile that predates calibration documents", () => {
    const state = migrate({legacyReady: true});
    assert.equal(state.initialCompletedAtMs, T0);
    assert.deepEqual(memberCoreSet(state, DAY1, SEQ).contentIds, v(1, 5));
  });

  it("is deterministic: the same history gives the same state", () => {
    const input = {
      legacyReady: true,
      legacyCompletedCount: 15,
      legacyCompletedAtMs: T0 - 5 * 86_400_000,
      interactions: new Map([["v2", {rating: "funny"}]]),
    };
    assert.deepEqual(migrate(input), migrate(input));
  });
});

describe("stored state", () => {
  it("drops ids that are not in the sequence and anything malformed", () => {
    const state = parseHumorCoreState(
      {
        answers: {
          v1: {rating: "funny", dayId: DAY1, answeredAtMs: 5, source: "core"},
          ext_giphy_x: {rating: "funny", dayId: DAY1, answeredAtMs: 5},
          v2: {rating: "hilarious"},
          v3: "funny",
        },
        waived: {v4: {reason: "reported", dayId: DAY1, atMs: 1}, nope: {reason: "reported"}},
        mediaFailures: {v5: {days: [DAY1, DAY1, "soon"], lastAtMs: 3}, v6: {days: []}},
        initialCompletedAtMs: "yesterday",
        today: {dayId: DAY1, contentIds: ["v1", "zzz", 7], kind: "weekly", completedAtMs: null},
        completedDays: -4,
      },
      SEQ,
    );
    assert.deepEqual(Object.keys(state.answers), ["v1"]);
    assert.deepEqual(Object.keys(state.waived), ["v4"]);
    assert.deepEqual(state.mediaFailures, {v5: {days: [DAY1], lastAtMs: 3}});
    assert.equal(state.initialCompletedAtMs, null);
    assert.deepEqual(state.today.contentIds, ["v1"]);
    assert.equal(state.today.kind, null);
    assert.equal(state.completedDays, 0);
  });

  it("parses a missing document as a fresh member", () => {
    assert.deepEqual(parseHumorCoreState(undefined, SEQ), defaultHumorCoreState());
  });

  it("survives a round trip through storage", () => {
    const state = rate(calibratedOnDay1(), day(2), v(16, 18)).state;
    assert.deepEqual(parseHumorCoreState(JSON.parse(JSON.stringify(state)), SEQ), state);
  });
});

describe("shared-content comparison", () => {
  it("compares two members over the canonical ids they both rated — a missing rating is not neutral", () => {
    const a = rate(defaultHumorCoreState(), DAY1, v(1, 6), {rating: "very_funny"}).state;
    let b = rate(defaultHumorCoreState(), DAY1, v(1, 3), {rating: "very_funny"}).state;
    b = applyCoreMediaFailure({
      state: b,
      set: memberCoreSet(b, DAY1, SEQ),
      id: "v4",
      nowMs: T0,
      sequence: SEQ,
    }).state;
    const result = dailyResponseAgreement(coreRatedAnswers(a), coreRatedAnswers(b));
    assert.equal(result.sharedDailyItemCount, 3);
    assert.equal(result.dailyResponseAgreement, 100);
  });

  it("gives the same prefix to everyone who has rated the same number of entries", () => {
    const paths = [
      // one long sitting, then daily
      () => {
        let s = calibratedOnDay1();
        s = rate(s, day(2)).state;
        return rate(s, day(3)).state;
      },
      // calibration over three days, then a week away, then daily
      () => {
        let s = rate(defaultHumorCoreState(), DAY1, v(1, 4)).state;
        s = rate(s, day(2), v(5, 9)).state;
        s = rate(s, day(3)).state;
        s = rate(s, day(11)).state;
        return rate(s, day(12)).state;
      },
    ];
    for (const path of paths) {
      assert.deepEqual([...coreRatedAnswers(path()).keys()], v(1, 25));
    }
  });
});
