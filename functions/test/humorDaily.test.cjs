/**
 * Daily Humor Evolution — backend contract.
 *
 * Pure rules (canonical day, pacing, content eligibility, deterministic
 * diverse selection, validation, pairwise agreement) and the Firestore
 * service on the in-memory double: one manifest per day for everyone,
 * atomic publish, resumable idempotent progress through the same feedback
 * transaction as the Humor Lab, explicit versioned repair, emulator-only
 * clock.
 */
const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");

const daily = require("../lib/humor/daily.js");
const service = require("../lib/humor/dailyService.js");
const {seedCalibrationCatalog} = require("../lib/humor/calibrationCatalog.js");
const {parseHumorContent} = require("../lib/humor/contentRepository.js");
const {submitHumorFeedbackTx} = require("../lib/humor/feedback.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");

const {
  DAILY_HUMOR_CONFIG,
  canonicalDayId,
  nextCanonicalDayStartMs,
  isDayId,
  shiftDayId,
  dailyEligibility,
  dailyIneligibility,
  isMotionContent,
  selectDailySet,
  selectRepairItem,
  validateDailySet,
  dailyResponseAgreement,
  ratedDailyAnswers,
  parseDailyAnswers,
  dailyProgress,
} = daily;

const DAY = 24 * 60 * 60 * 1000;
// 2026-09-29 12:00 in Istanbul (UTC+3).
const NOW = Date.UTC(2026, 8, 29, 9, 0, 0);
const TODAY = "2026-09-29";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function contentDoc(id, overrides = {}) {
  const category = overrides.category ?? "sarcasm";
  const data = {
    type: "meme",
    language: "en",
    category,
    humorTags: [],
    humorVector: {[category]: 0.8},
    media: {
      downloadUrl: `https://media.giphy.com/media/${id}/giphy.webp`,
      thumbUrl: `https://media.giphy.com/media/${id}/giphy_s.gif`,
      aspectRatio: 1.5,
    },
    safetyStatus: "approved",
    active: true,
    source: {type: "licensed_api", provider: "giphy"},
    sourceTrust: "curated",
    calibrationEligible: false,
    calibrationSlot: null,
    ...overrides.data,
  };
  return {data, doc: parseHumorContent(id, data)};
}

/** A pool with [perCategory] items in each of the eleven categories. */
function syntheticPool(perCategory = 3, prefix = "p") {
  const out = [];
  for (const category of HUMOR_CATEGORIES) {
    for (let i = 0; i < perCategory; i++) {
      out.push(contentDoc(`${prefix}_${category}_${i}`, {category}).doc);
    }
  }
  return out;
}

async function seededDb(extra = {}) {
  const db = createFakeFirestore(extra);
  await seedCalibrationCatalog(db);
  return db;
}

function calibrated(uid, completedAtMs, interactionCount = 15) {
  return {
    [`users/${uid}/humor/calibration`]: {
      version: 1,
      completedCount: 15,
      complete: true,
      completedAt: Timestamp.fromMillis(completedAtMs),
    },
    [`users/${uid}/humor/summary`]: {
      vector: {sarcasm: 70, wordplay: 60},
      confidence: 0.4,
      interactionCount,
      exploredCategories: [],
      version: 1,
    },
  };
}

function seedUsers(db, entries) {
  for (const [path, data] of Object.entries(entries)) {
    db._store.set(path, data);
  }
}

const RATINGS = ["very_funny", "funny", "neutral", "not_funny", "not_at_all"];

async function answer(db, uid, contentId, rating, extra = {}) {
  return service.submitDailyHumorResponse({
    db,
    uid,
    nowMs: NOW,
    response: {
      dayId: TODAY,
      contentId,
      rating: extra.skipped ? null : rating,
      skipped: extra.skipped === true,
      dwellMs: 1000,
      replayCount: 0,
    },
  });
}

// ---------------------------------------------------------------------------
// Canonical day
// ---------------------------------------------------------------------------

describe("canonical day", () => {
  it("turns over at midnight Europe/Istanbul (UTC+3), not at UTC midnight", () => {
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
});

// ---------------------------------------------------------------------------
// Pacing
// ---------------------------------------------------------------------------

describe("member eligibility (pacing)", () => {
  it("locks members who have not finished calibration", () => {
    assert.deepEqual(dailyEligibility({ready: false, completedAtMs: null, todayId: TODAY}), {
      eligible: false,
      reason: "calibration_incomplete",
    });
  });

  it("starts the day after calibration completes, never the same day", () => {
    const sameDayLate = Date.UTC(2026, 8, 29, 20, 30);
    assert.deepEqual(dailyEligibility({ready: true, completedAtMs: sameDayLate, todayId: TODAY}), {
      eligible: false,
      reason: "starts_tomorrow",
    });
    const yesterdayLate = Date.UTC(2026, 8, 28, 20, 59);
    assert.deepEqual(
      dailyEligibility({ready: true, completedAtMs: yesterdayLate, todayId: TODAY}),
      {eligible: true},
    );
  });

  it("lets existing calibrated members in without redoing calibration", () => {
    assert.deepEqual(
      dailyEligibility({ready: true, completedAtMs: NOW - 40 * DAY, todayId: TODAY}),
      {eligible: true},
    );
    // A legacy ready profile carries no completion stamp at all.
    assert.deepEqual(dailyEligibility({ready: true, completedAtMs: null, todayId: TODAY}), {
      eligible: true,
    });
  });
});

// ---------------------------------------------------------------------------
// Content eligibility
// ---------------------------------------------------------------------------

describe("daily content eligibility", () => {
  it("accepts provider GIFs shown as animated images and real videos", () => {
    assert.equal(dailyIneligibility(contentDoc("a").doc), null);
    const video = contentDoc("v", {
      data: {type: "video", media: {downloadUrl: "https://media.giphy.com/media/v/giphy.mp4"}},
    }).doc;
    assert.equal(isMotionContent(video), true);
    assert.equal(dailyIneligibility(video), null);
  });

  it("rejects text, static images, unservable, QA fixtures, bad hosts and signal-free items", () => {
    const cases = {
      "not-motion": [
        contentDoc("t", {data: {type: "text", media: {textBody: "joke"}}}).doc,
        contentDoc("i", {data: {type: "image"}}).doc,
        contentDoc("s", {data: {media: {downloadUrl: "https://media.giphy.com/media/s/still.png"}}})
          .doc,
        contentDoc("m", {data: {source: {type: "internal"}}}).doc,
      ],
      "not-servable": [
        contentDoc("x", {data: {active: false}}).doc,
        contentDoc("y", {data: {safetyStatus: "needs_review"}}).doc,
      ],
      "qa-fixture": [contentDoc("q", {data: {sourceTrust: "qa_fixture"}}).doc],
      "media-unhealthy": [
        contentDoc("h", {data: {media: {downloadUrl: "http://media.giphy.com/media/h/giphy.webp"}}})
          .doc,
        contentDoc("e", {data: {media: {downloadUrl: "https://evil.example.com/e.webp"}}}).doc,
        contentDoc("r", {
          data: {media: {downloadUrl: "https://media.giphy.com/media/r/giphy.webp", aspectRatio: 9}},
        }).doc,
      ],
      "not-humor-relevant": [contentDoc("z", {data: {humorVector: {}}}).doc],
    };
    for (const [reason, docs] of Object.entries(cases)) {
      for (const doc of docs) {
        assert.equal(dailyIneligibility(doc), reason, doc.contentId);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

describe("daily set selection", () => {
  it("is deterministic: same pool and day, same ten items in the same order", () => {
    const pool = syntheticPool(3);
    const a = selectDailySet({dayId: TODAY, pool, recentByDay: []});
    const b = selectDailySet({dayId: TODAY, pool: [...pool].reverse(), recentByDay: []});
    assert.equal(a.ok, true);
    assert.deepEqual(
      a.items.map((c) => c.contentId),
      b.items.map((c) => c.contentId),
    );
  });

  it("publishes ten unique eligible items spread across the dimensions", () => {
    const result = selectDailySet({dayId: TODAY, pool: syntheticPool(3), recentByDay: []});
    assert.equal(result.ok, true);
    assert.equal(result.items.length, DAILY_HUMOR_CONFIG.setSize);
    assert.equal(validateDailySet(result.items), null);
    const counts = {};
    for (const item of result.items) counts[item.category] = (counts[item.category] ?? 0) + 1;
    assert.ok(Object.values(counts).every((n) => n <= DAILY_HUMOR_CONFIG.maxPerCategory));
    // Breadth first: with eleven dimensions available, ten distinct ones.
    assert.equal(Object.keys(counts).length, 10);
  });

  it("changes with the day and keeps recent days out when the pool allows", () => {
    const pool = syntheticPool(3);
    const day1 = selectDailySet({dayId: TODAY, pool, recentByDay: []});
    const day2 = selectDailySet({
      dayId: shiftDayId(TODAY, 1),
      pool,
      recentByDay: [day1.items.map((c) => c.contentId)],
    });
    assert.equal(day2.ok, true);
    assert.equal(day2.recentDaysExcluded, 1);
    const overlap = day2.items.filter((c) => day1.items.some((d) => d.contentId === c.contentId));
    assert.equal(overlap.length, 0);
  });

  it("relaxes the recent-repeat window only as far as needed, never padding with ineligible items", () => {
    // 11 categories × 1 item: yesterday used 10 of them, so excluding
    // yesterday leaves one — the window relaxes to 0 rather than failing.
    const pool = syntheticPool(1);
    const day1 = selectDailySet({dayId: TODAY, pool, recentByDay: []});
    const day2 = selectDailySet({
      dayId: shiftDayId(TODAY, 1),
      pool: [...pool, contentDoc("bad", {data: {type: "text"}}).doc],
      recentByDay: [day1.items.map((c) => c.contentId)],
    });
    assert.equal(day2.ok, true);
    assert.equal(day2.recentDaysExcluded, 0);
    assert.ok(day2.items.every((c) => c.contentId !== "bad"));
  });

  it("reports insufficient content instead of filling: too few items or too little variety", () => {
    const few = selectDailySet({dayId: TODAY, pool: syntheticPool(3).slice(0, 9), recentByDay: []});
    assert.deepEqual(few.ok, false);
    assert.equal(few.reason, "insufficient-content");
    // Twenty items but only two dimensions: the cap makes a valid set impossible.
    const narrow = [];
    for (let i = 0; i < 10; i++) {
      narrow.push(contentDoc(`n_s_${i}`, {category: "sarcasm"}).doc);
      narrow.push(contentDoc(`n_a_${i}`, {category: "absurd"}).doc);
    }
    assert.equal(selectDailySet({dayId: TODAY, pool: narrow, recentByDay: []}).ok, false);
    const onlyText = syntheticPool(3).map((c) => ({...c, type: "text"}));
    assert.equal(selectDailySet({dayId: TODAY, pool: onlyText, recentByDay: []}).ok, false);
  });

  it("prefers non-anchor items so the daily set does not re-ask calibration anchors", () => {
    const open = syntheticPool(1, "open");
    const anchors = syntheticPool(2, "anchor").map((c) => ({
      ...c,
      calibration: {eligible: true, slot: "anchor_wit", version: 1},
    }));
    const result = selectDailySet({dayId: TODAY, pool: [...anchors, ...open], recentByDay: []});
    assert.equal(result.ok, true);
    assert.ok(result.items.every((c) => c.contentId.startsWith("open_")));
  });

  it("validation names the problem with a candidate set", () => {
    const items = selectDailySet({dayId: TODAY, pool: syntheticPool(3), recentByDay: []}).items;
    assert.equal(validateDailySet(items.slice(0, 9)), "wrong-size");
    assert.equal(validateDailySet([...items.slice(0, 9), items[0]]), "duplicate-item");
    const text = {...items[9], type: "text"};
    assert.equal(validateDailySet([...items.slice(0, 9), text]), "ineligible-item");
    const sarcasm = syntheticPool(3).filter((c) => c.category === "sarcasm");
    const rest = items.filter((c) => c.category !== "sarcasm").slice(0, 7);
    assert.equal(validateDailySet([...sarcasm, ...rest]), "category-cap");
  });

  it("repair picks an eligible replacement that keeps the set valid and never the removed item", () => {
    const pool = syntheticPool(3);
    const items = selectDailySet({dayId: TODAY, pool, recentByDay: []}).items;
    const removed = items[4].contentId;
    const current = items.map((c, i) => (i === 4 ? null : c));
    const replacement = selectRepairItem({
      dayId: TODAY,
      current,
      index: 4,
      pool,
      version: 1,
      excludeIds: [removed],
    });
    assert.ok(replacement);
    assert.notEqual(replacement.contentId, removed);
    assert.ok(items.every((c) => c.contentId !== replacement.contentId));
    const next = items.slice();
    next[4] = replacement;
    assert.equal(validateDailySet(next), null);
  });

  it("works on the real curated catalogue", async () => {
    const db = await seededDb();
    const pool = await service.loadDailyPool(db);
    assert.ok(pool.length >= DAILY_HUMOR_CONFIG.setSize, `pool ${pool.length}`);
    const day1 = selectDailySet({dayId: TODAY, pool, recentByDay: []});
    assert.equal(day1.ok, true);
    assert.equal(validateDailySet(day1.items), null);
    // Three consecutive days stay publishable on the curated catalogue alone.
    let recent = [day1.items.map((c) => c.contentId)];
    for (let d = 1; d <= 3; d++) {
      const next = selectDailySet({dayId: shiftDayId(TODAY, d), pool, recentByDay: recent});
      assert.equal(next.ok, true, `day +${d}`);
      recent = [next.items.map((c) => c.contentId), ...recent].slice(0, 2);
    }
  });
});

// ---------------------------------------------------------------------------
// Agreement
// ---------------------------------------------------------------------------

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

  it("reads rated answers only — media skips are never evidence", () => {
    const rated = ratedDailyAnswers([
      {
        total: 10,
        answers: {
          0: {contentId: "c1", rating: "funny", skipped: false},
          1: {contentId: "c2", rating: null, skipped: true},
          12: {contentId: "cX", rating: "funny", skipped: false},
        },
      },
    ]);
    assert.deepEqual([...rated.entries()], [["c1", "funny"]]);
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
      assert.equal(/dailyResponseAgreement|humorDaily|daily\.js/.test(text), false, file);
    }
  });
});

describe("progress helpers", () => {
  it("resumes at the first unanswered slot and completes at the last", () => {
    const answers = parseDailyAnswers(
      {0: {contentId: "a", rating: "funny"}, 1: {contentId: "b", rating: "funny"}, 3: {contentId: "d", rating: "funny"}},
      10,
    );
    assert.deepEqual(dailyProgress(answers, 10), {answeredCount: 3, completed: false, nextIndex: 2});
    const all = parseDailyAnswers(
      Object.fromEntries(Array.from({length: 10}, (_, i) => [i, {contentId: `c${i}`, rating: "funny"}])),
      10,
    );
    assert.deepEqual(dailyProgress(all, 10), {answeredCount: 10, completed: true, nextIndex: 10});
  });
});

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

describe("daily service", () => {
  let savedEmulatorFlag;
  beforeEach(() => {
    savedEmulatorFlag = process.env.FUNCTIONS_EMULATOR;
    delete process.env.FUNCTIONS_EMULATOR;
  });
  afterEach(() => {
    if (savedEmulatorFlag === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = savedEmulatorFlag;
  });

  async function twoCalibratedUsers() {
    const db = await seededDb();
    seedUsers(db, {
      ...calibrated("uA", NOW - 2 * DAY),
      ...calibrated("uB", NOW - 30 * DAY, 60),
    });
    return db;
  }

  it("gives two members the same ten ids in the same order", async () => {
    const db = await twoCalibratedUsers();
    const a = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const b = await service.getDailyHumorSetView({db, uid: "uB", nowMs: NOW});
    assert.equal(a.status, "ready");
    assert.equal(a.dayId, TODAY);
    assert.equal(a.items.length, 10);
    assert.deepEqual(
      a.items.map((i) => i.contentId),
      b.items.map((i) => i.contentId),
    );
    assert.deepEqual(db._store.get(`humorDailySets/${TODAY}`).contentIds, a.items.map((i) => i.contentId));
  });

  it("serves feed-safe cards: no vectors, safety flags or calibration slots", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    for (const item of view.items) {
      assert.equal("humorVector" in item, false);
      assert.equal("safetyFlags" in item, false);
      assert.equal("calibration" in item, false);
      assert.equal(item.calibrationStage, null);
      assert.ok(item.media.downloadUrl.startsWith("https://"));
    }
  });

  it("locks contrast members: uncalibrated, and calibrated today", async () => {
    const db = await seededDb();
    seedUsers(db, calibrated("uToday", NOW - 3600_000));
    const fresh = await service.getDailyHumorSetView({db, uid: "uNew", nowMs: NOW});
    assert.deepEqual([fresh.status, fresh.lockedReason, fresh.items.length], [
      "locked",
      "calibration_incomplete",
      0,
    ]);
    const today = await service.getDailyHumorSetView({db, uid: "uToday", nowMs: NOW});
    assert.deepEqual([today.status, today.lockedReason], ["locked", "starts_tomorrow"]);
    // Locked members do not trigger a publish.
    assert.equal(db._store.has(`humorDailySets/${TODAY}`), false);
  });

  it("admits a legacy ready profile with no calibration document", async () => {
    const db = await seededDb();
    seedUsers(db, {
      "users/uOld/humor/summary": {vector: {dry: 70}, interactionCount: 20, version: 1},
    });
    const view = await service.getDailyHumorSetView({db, uid: "uOld", nowMs: NOW});
    assert.equal(view.status, "ready");
  });

  it("publishes exactly once under concurrent first requests, then never reshuffles", async () => {
    const db = await seededDb();
    const results = await Promise.all(
      Array.from({length: 6}, () =>
        service.ensureDailySet({db, dayId: TODAY, nowMs: NOW, publishedBy: "auto"}),
      ),
    );
    assert.equal(results.filter((r) => r.created).length, 1);
    const ids = results.map((r) => r.manifest.contentIds.join(","));
    assert.equal(new Set(ids).size, 1);
    // New content arriving later does not change a published day.
    for (const c of syntheticPool(2, "late")) {
      db._store.set(`humorContent/${c.contentId}`, contentDoc(c.contentId, {category: c.category}).data);
    }
    const again = await service.ensureDailySet({db, dayId: TODAY, nowMs: NOW + 5000, publishedBy: "auto"});
    assert.equal(again.created, false);
    assert.equal(again.manifest.contentIds.join(","), ids[0]);
  });

  it("records progress, resumes at 3/10 and 9/10, and completes on the 10th answer", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const ids = view.items.map((i) => i.contentId);
    for (let i = 0; i < 3; i++) await answer(db, "uA", ids[i], RATINGS[i % 5]);
    const at3 = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.deepEqual([at3.answeredCount, at3.nextIndex, at3.completed], [3, 3, false]);
    assert.deepEqual(at3.items.map((i) => i.contentId), ids);
    assert.deepEqual(at3.answers.map((a) => [a.index, a.contentId]), [[0, ids[0]], [1, ids[1]], [2, ids[2]]]);

    for (let i = 3; i < 9; i++) await answer(db, "uA", ids[i], RATINGS[i % 5]);
    const at9 = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.deepEqual([at9.answeredCount, at9.nextIndex, at9.completed], [9, 9, false]);

    const last = await answer(db, "uA", ids[9], "funny");
    assert.deepEqual([last.answeredCount, last.completed, last.nextIndex, last.total], [10, true, 10, 10]);
    const stored = db._store.get(`users/uA/humorDaily/${TODAY}`);
    assert.equal(stored.completed, true);
    assert.ok(stored.completedAt);
    assert.ok(stored.startedAt);
    // Member B's progress is independent.
    const b = await service.getDailyHumorSetView({db, uid: "uB", nowMs: NOW});
    assert.equal(b.answeredCount, 0);
  });

  it("updates the lifetime profile once per response, even on double taps and retries", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const id = view.items[0].contentId;
    const before = db._store.get("users/uA/humor/summary").interactionCount;
    const [r1, r2] = await Promise.all([
      answer(db, "uA", id, "very_funny"),
      answer(db, "uA", id, "very_funny"),
    ]);
    const r3 = await answer(db, "uA", id, "very_funny");
    assert.equal(db._store.get("users/uA/humor/summary").interactionCount, before + 1);
    assert.deepEqual([r1.answeredCount, r2.answeredCount, r3.answeredCount], [1, 1, 1]);
    assert.equal(r3.alreadyAnswered, true);
    assert.equal(db._store.get(`users/uA/humorInteractions/${id}`).rating, "very_funny");
  });

  it("re-rating a slot replaces the earlier contribution instead of adding one", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const id = view.items[0].contentId;
    await answer(db, "uA", id, "very_funny");
    const afterFirst = db._store.get("users/uA/humor/summary");
    const changed = await answer(db, "uA", id, "not_at_all");
    const afterSecond = db._store.get("users/uA/humor/summary");
    assert.equal(changed.answeredCount, 1);
    assert.equal(afterSecond.interactionCount, afterFirst.interactionCount);
    assert.equal(db._store.get(`users/uA/humorInteractions/${id}`).rating, "not_at_all");
    assert.equal(db._store.get(`users/uA/humorDaily/${TODAY}`).answers["0"].rating, "not_at_all");
    // Back to the first rating lands where a single first rating would have.
    await answer(db, "uA", id, "very_funny");
    const restored = db._store.get("users/uA/humor/summary").vector;
    for (const [dim, value] of Object.entries(afterFirst.vector)) {
      assert.ok(Math.abs(restored[dim] - value) < 1e-9, dim);
    }
  });

  it("a daily answer for an item already rated in the Lab follows the same re-rating rules", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const id = view.items[0].contentId;
    await submitHumorFeedbackTx({db, uid: "uA", contentId: id, rating: "funny"});
    const count = db._store.get("users/uA/humor/summary").interactionCount;
    const same = await answer(db, "uA", id, "funny");
    assert.equal(same.answeredCount, 1);
    assert.equal(db._store.get("users/uA/humor/summary").interactionCount, count);
  });

  it("a media skip completes its slot without teaching the profile, and never overrides a rating", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const [first, second] = view.items.map((i) => i.contentId);
    const profileBefore = JSON.stringify(db._store.get("users/uA/humor/summary"));
    const skipped = await answer(db, "uA", first, null, {skipped: true});
    assert.equal(skipped.answeredCount, 1);
    assert.equal(JSON.stringify(db._store.get("users/uA/humor/summary")), profileBefore);
    assert.equal(db._store.get(`users/uA/humorInteractions/${first}`).skipReason, "media_failed");

    await answer(db, "uA", second, "funny");
    const again = await answer(db, "uA", second, null, {skipped: true});
    assert.equal(again.alreadyAnswered, true);
    assert.equal(db._store.get(`users/uA/humorDaily/${TODAY}`).answers["1"].rating, "funny");
  });

  it("rejects a closed day, an unknown item and an ineligible member", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const id = view.items[0].contentId;
    const reject = async (promise, reason) =>
      assert.rejects(promise, (e) => e instanceof service.DailyResponseRejected && e.reason === reason);

    await reject(
      service.submitDailyHumorResponse({
        db,
        uid: "uA",
        nowMs: NOW,
        response: {dayId: "2026-09-28", contentId: id, rating: "funny", skipped: false, dwellMs: 0, replayCount: 0},
      }),
      "day-closed",
    );
    // Answering yesterday's set after midnight: the day moved on.
    await reject(
      service.submitDailyHumorResponse({
        db,
        uid: "uA",
        nowMs: NOW + DAY,
        response: {dayId: TODAY, contentId: id, rating: "funny", skipped: false, dwellMs: 0, replayCount: 0},
      }),
      "day-closed",
    );
    const outsider = Object.keys(Object.fromEntries(db._store))
      .filter((p) => p.startsWith("humorContent/"))
      .map((p) => p.split("/")[1])
      .find((cid) => !view.items.some((i) => i.contentId === cid));
    await reject(answer(db, "uA", outsider, "funny"), "slot-replaced");
    await reject(answer(db, "uNobody", id, "funny"), "not-eligible");
    assert.equal(db._store.has(`users/uNobody/humorDaily/${TODAY}`), false);
  });

  it("validates callable input: day id, content id, rating, and only media skips", () => {
    const parse = service.parseDailyResponseInput;
    assert.equal(parse({dayId: TODAY, contentId: "c1", rating: "funny"}).ok, true);
    assert.equal(parse({dayId: TODAY, contentId: "c1", skipped: true, skipReason: "media_failed"}).ok, true);
    assert.deepEqual(parse({dayId: TODAY, contentId: "c1", skipped: true}), {ok: false, field: "skipReason"});
    assert.deepEqual(parse({dayId: TODAY, contentId: "c1", skipped: true, skipReason: "user"}), {
      ok: false,
      field: "skipReason",
    });
    assert.deepEqual(parse({dayId: "tomorrow", contentId: "c1", rating: "funny"}), {ok: false, field: "dayId"});
    assert.deepEqual(parse({dayId: TODAY, contentId: "a/b", rating: "funny"}), {ok: false, field: "contentId"});
    assert.deepEqual(parse({dayId: TODAY, contentId: "c1", rating: "lol"}), {ok: false, field: "rating"});
    assert.deepEqual(parse(null), {ok: false, field: "dayId"});
  });

  it("shows a clear not-ready state instead of filler, and re-checks on a bounded interval", async () => {
    const db = createFakeFirestore({});
    seedUsers(db, calibrated("uA", NOW - 2 * DAY));
    seedUsers(db, calibrated("uB", NOW - 2 * DAY));
    const [first, concurrent] = await Promise.all([
      service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW}),
      service.getDailyHumorSetView({db, uid: "uB", nowMs: NOW}),
    ]);
    assert.equal(concurrent.status, "not_ready");
    assert.deepEqual([first.status, first.items.length], ["not_ready", 0]);
    assert.equal(db._store.get(`humorDailySets/${TODAY}`).status, "not_ready");

    for (const c of syntheticPool(2)) {
      db._store.set(`humorContent/${c.contentId}`, contentDoc(c.contentId, {category: c.category}).data);
    }
    const soon = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW + 60_000});
    assert.equal(soon.status, "not_ready");
    const later = await service.getDailyHumorSetView({
      db,
      uid: "uA",
      nowMs: NOW + DAILY_HUMOR_CONFIG.notReadyRecheckMs + 1,
    });
    assert.equal(later.status, "ready");
    assert.equal(later.items.length, 10);
  });

  it("drops a slot whose item was taken down, rather than swapping it silently", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const ids = view.items.map((i) => i.contentId);
    await answer(db, "uA", ids[0], "funny");
    const doc = db._store.get(`humorContent/${ids[1]}`);
    db._store.set(`humorContent/${ids[1]}`, {...doc, safetyStatus: "needs_review"});
    const after = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.equal(after.total, 9);
    assert.deepEqual(after.items.map((i) => i.contentId), ids.filter((id) => id !== ids[1]));
    assert.deepEqual([after.answeredCount, after.nextIndex], [1, 1]);
    // The manifest itself is unchanged.
    assert.deepEqual(db._store.get(`humorDailySets/${TODAY}`).contentIds, ids);
    await assert.rejects(answer(db, "uA", ids[1], "funny"), (e) => e.reason === "slot-replaced");
    // Nine answers complete the nine-slot day.
    for (const id of ids.filter((x) => x !== ids[1] && x !== ids[0])) await answer(db, "uA", id, "neutral");
    const done = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.deepEqual([done.completed, done.answeredCount, done.total], [true, 9, 9]);
  });

  it("repairs a slot explicitly: versioned, recorded, validated; earlier answers stand", async () => {
    const db = await twoCalibratedUsers();
    const view = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    const ids = view.items.map((i) => i.contentId);
    await answer(db, "uA", ids[2], "funny");
    const result = await service.repairDailySlot({
      db,
      dayId: TODAY,
      index: 2,
      reason: "media broken",
      adminUid: "admin1",
      nowMs: NOW,
    });
    assert.equal(result.version, 2);
    assert.equal(result.from, ids[2]);
    const manifest = db._store.get(`humorDailySets/${TODAY}`);
    assert.equal(manifest.version, 2);
    assert.equal(manifest.contentIds[2], result.to);
    assert.equal(manifest.repairs.length, 1);
    assert.equal(manifest.repairs[0].by, "admin1");
    assert.ok(!ids.includes(result.to));
    // A's answer to the old item still fills slot 2; B meets the replacement.
    const a = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.deepEqual([a.setVersion, a.answeredCount], [2, 1]);
    const b = await service.getDailyHumorSetView({db, uid: "uB", nowMs: NOW});
    assert.equal(b.items[2].contentId, result.to);
  });

  it("lets admins name only today or tomorrow outside the emulator", () => {
    assert.equal(service.adminDayAllowed(TODAY, TODAY, false), true);
    assert.equal(service.adminDayAllowed("2026-09-30", TODAY, false), true);
    assert.equal(service.adminDayAllowed("2026-10-05", TODAY, false), false);
    assert.equal(service.adminDayAllowed("2026-09-28", TODAY, false), false);
    assert.equal(service.adminDayAllowed("2026-10-05", TODAY, true), true);
    assert.equal(service.adminDayAllowed("nope", TODAY, true), false);
  });

  it("honours the test clock only inside the emulator, and a new day brings a new set", async () => {
    const db = await twoCalibratedUsers();
    db._store.set("devClock/humorDaily", {dayId: "2026-09-30"});
    assert.equal(await service.resolveDailyToday(db, NOW), TODAY);

    const today = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    process.env.FUNCTIONS_EMULATOR = "true";
    assert.equal(await service.resolveDailyToday(db, NOW), "2026-09-30");
    const tomorrow = await service.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.equal(tomorrow.dayId, "2026-09-30");
    assert.equal(tomorrow.status, "ready");
    assert.equal(tomorrow.answeredCount, 0);
    const overlap = tomorrow.items.filter((i) => today.items.some((t) => t.contentId === i.contentId));
    assert.equal(overlap.length, 0, "yesterday's items are kept out when the pool allows");
    // A member who calibrated "today" in real time is eligible on the next test day.
    seedUsers(db, calibrated("uToday", NOW - 3600_000));
    const next = await service.getDailyHumorSetView({db, uid: "uToday", nowMs: NOW});
    assert.equal(next.status, "ready");
  });
});
