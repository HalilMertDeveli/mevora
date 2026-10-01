/**
 * The humor day — backend contract.
 *
 * The canonical day every humor rule runs on, the pairwise agreement over
 * shared content, and the day documents the old global daily set left behind.
 * What a member gets on a day is the Core sequence's business: see
 * humorCoreSchedule.test.cjs and humorCoreService.test.cjs.
 */
const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {
  DAILY_HUMOR_CONFIG,
  canonicalDayId,
  nextCanonicalDayStartMs,
  isDayId,
  shiftDayId,
  dailyResponseAgreement,
  ratedDailyAnswers,
  parseDailyAnswers,
  timestampMs,
} = require("../lib/humor/daily.js");

// 2026-09-29 12:00 in Istanbul (UTC+3).
const NOW = Date.UTC(2026, 8, 29, 9, 0, 0);

describe("canonical day", () => {
  it("turns over at midnight Europe/Istanbul (UTC+3), not at UTC midnight", () => {
    assert.equal(DAILY_HUMOR_CONFIG.canonicalUtcOffsetMinutes, 180);
    assert.equal(canonicalDayId(Date.UTC(2026, 8, 28, 20, 59, 59)), "2026-09-28");
    assert.equal(canonicalDayId(Date.UTC(2026, 8, 28, 21, 0, 0)), "2026-09-29");
    assert.equal(canonicalDayId(Date.UTC(2026, 8, 29, 20, 59, 59)), "2026-09-29");
    assert.equal(nextCanonicalDayStartMs(NOW), Date.UTC(2026, 8, 29, 21, 0, 0));
  });

  it("matches the boundary daily Picks already use", () => {
    const {logicalDayKey} = require("../lib/picks/lifecycle.js");
    for (const ms of [NOW, NOW + 11 * 3600_000, NOW + 12 * 3600_000, NOW - 9 * 3600_000]) {
      assert.equal(canonicalDayId(ms), logicalDayKey(ms));
    }
  });

  it("validates and shifts day ids", () => {
    assert.equal(isDayId("2026-09-29"), true);
    assert.equal(isDayId("2026-02-30"), false);
    assert.equal(isDayId("2026-9-29"), false);
    assert.equal(isDayId(20260929), false);
    assert.equal(shiftDayId("2026-09-30", 1), "2026-10-01");
    assert.equal(shiftDayId("2026-01-01", -1), "2025-12-31");
  });

  it("reads a stored timestamp in any of its shapes", () => {
    assert.equal(timestampMs(1234), 1234);
    assert.equal(timestampMs(new Date(5678)), 5678);
    assert.equal(timestampMs({toMillis: () => 91}), 91);
    assert.equal(timestampMs({_seconds: 2}), 2000);
    assert.equal(timestampMs(undefined), null);
  });
});

describe("pairwise shared-response agreement", () => {
  const map = (entries) => new Map(Object.entries(entries));

  it("counts only content both members rated; missing is not neutral", () => {
    const a = map({c1: "very_funny", c2: "funny", c3: "neutral", c4: "very_funny"});
    const b = map({c1: "very_funny", c2: "funny", c3: "neutral", c9: "not_at_all"});
    assert.deepEqual(dailyResponseAgreement(a, b), {
      sharedDailyItemCount: 3,
      dailyResponseAgreement: 100,
    });
  });

  it("is bounded, symmetric and deterministic", () => {
    const a = map({c1: "very_funny", c2: "very_funny", c3: "very_funny"});
    const b = map({c1: "not_at_all", c2: "not_at_all", c3: "not_at_all"});
    assert.deepEqual(dailyResponseAgreement(a, b), {
      sharedDailyItemCount: 3,
      dailyResponseAgreement: 0,
    });
    const c = map({c1: "funny", c2: "not_funny", c3: "neutral", c4: "very_funny"});
    const d = map({c1: "very_funny", c2: "not_at_all", c3: "funny", c4: "funny"});
    const ab = dailyResponseAgreement(c, d);
    assert.deepEqual(ab, dailyResponseAgreement(d, c));
    assert.ok(ab.dailyResponseAgreement >= 0 && ab.dailyResponseAgreement <= 100);
  });

  it("has no score below the shared-item floor", () => {
    const a = map({c1: "funny", c2: "funny"});
    assert.deepEqual(dailyResponseAgreement(a, a), {
      sharedDailyItemCount: 2,
      dailyResponseAgreement: null,
    });
  });

  it("never touches Discover ranking or the main compatibility engine", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const src = path.join(__dirname, "..", "src");
    for (const file of [
      "compatibility/compatibilityEngine.ts",
      "discoveryMatching.ts",
      "matchScore.ts",
      "humor/compatibility.ts",
    ]) {
      const text = fs.readFileSync(path.join(src, file), "utf8");
      assert.equal(
        /dailyResponseAgreement|coreRatedAnswers|humorDaily|daily\.js/.test(text),
        false,
        file,
      );
    }
  });
});

describe("day documents written by the old daily set", () => {
  it("still read as rated answers — media skips are never evidence", () => {
    const rated = ratedDailyAnswers([
      {
        total: 10,
        answers: {
          0: {contentId: "c1", rating: "funny", skipped: false},
          1: {contentId: "c2", rating: null, skipped: true},
          9: {contentId: "c9", rating: "not_funny", skipped: false},
        },
      },
      {answers: {3: {contentId: "c4", rating: "very_funny", skipped: false}}},
    ]);
    assert.deepEqual(
      [...rated.entries()],
      [
        ["c1", "funny"],
        ["c9", "not_funny"],
        ["c4", "very_funny"],
      ],
    );
  });

  it("are parsed defensively, with no set size assumed", () => {
    const answers = parseDailyAnswers(
      {
        0: {contentId: "a", rating: "funny"},
        7: {contentId: "h", rating: "funny"},
        "-1": {contentId: "x", rating: "funny"},
        "1.5": {contentId: "y", rating: "funny"},
        2: "funny",
        3: {rating: "funny"},
      },
      8,
    );
    assert.deepEqual([...answers.keys()], [0, 7]);
    assert.equal(ratedDailyAnswers([{answers: {4242: {contentId: "z", rating: "funny"}}}]).size, 0);
    assert.equal(ratedDailyAnswers([{answers: null}, {}]).size, 0);
  });
});
