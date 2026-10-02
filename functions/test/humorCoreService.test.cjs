/**
 * Humor Core progression — the Firestore service on the in-memory double,
 * against the real curated catalogue and the real sequence.
 *
 * The server owns the day, the position and the content; a response is
 * accepted only for an entry of the set it computed; learning goes through
 * the unchanged feedback transaction; members from before the Core sequence
 * keep everything they had.
 */
const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");

const core = require("../lib/humor/coreService.js");
const daily = require("../lib/humor/dailyService.js");
const {DAILY_HUMOR_CONFIG} = require("../lib/humor/daily.js");
const {seedCalibrationCatalog} = require("../lib/humor/calibrationCatalog.js");
const {HUMOR_CORE, HUMOR_CORE_SEQUENCE} = require("../lib/humor/coreSequence.js");
const {humorScoreForPair, isHumorCalibrationReady} = require("../lib/humor/compatibility.js");

const DAY = 24 * 60 * 60 * 1000;
// 2026-10-01 12:00 in Istanbul (UTC+3).
const NOW = Date.UTC(2026, 9, 1, 9, 0, 0);
const TODAY = "2026-10-01";
/** The server clock on logical day [n] (1 = TODAY). */
const at = (n) => NOW + (n - 1) * DAY;
const dayId = (n) => new Date(at(n) + 3 * 3600_000).toISOString().slice(0, 10);

/** The id at position V[n]. */
const V = (n) => HUMOR_CORE_SEQUENCE[n - 1].id;
const Vs = (from, to) => Array.from({length: to - from + 1}, (_, i) => V(from + i));
const ids = (items) => items.map((item) => item.contentId);
/** A plain-data copy, so documents holding Timestamps compare by value. */
const plain = (value) => JSON.parse(JSON.stringify(value));

async function seededDb() {
  const db = createFakeFirestore();
  await seedCalibrationCatalog(db);
  return db;
}

const summary = (db, uid) => db._store.get(`users/${uid}/humor/summary`);
const calibration = (db, uid) => db._store.get(`users/${uid}/humor/calibration`);
const coreDoc = (db, uid) => db._store.get(`users/${uid}/humor/core`);
const interaction = (db, uid, id) => db._store.get(`users/${uid}/humorInteractions/${id}`);

function respond(db, uid, contentId, rating, n = 1, extra = {}) {
  return core.submitHumorCoreResponse({
    db,
    uid,
    nowMs: at(n),
    contentId,
    rating: extra.mediaFailed ? null : rating,
    mediaFailed: extra.mediaFailed === true,
    dwellMs: 1200,
    replayCount: 0,
    ...extra,
  });
}

async function rateAll(db, uid, contentIds, n = 1, ratingFor = () => "funny") {
  for (const id of contentIds) {
    await respond(db, uid, id, ratingFor(id), n);
  }
}

/** [uid] finishes V1–V15 on day [n]. */
async function calibrate(db, uid, n = 1, ratingFor) {
  await rateAll(db, uid, Vs(1, 15), n, ratingFor);
}

function dailyAnswer(db, uid, contentId, rating, n, overrides = {}) {
  return daily.submitDailyHumorResponse({
    db,
    uid,
    nowMs: at(n),
    response: {
      dayId: dayId(n),
      contentId,
      rating,
      skipped: false,
      dwellMs: 900,
      replayCount: 0,
      ...overrides,
    },
  });
}

/** A member who finished the old adaptive calibration [daysAgo] days ago. */
function legacyCalibrated(uid, daysAgo, interactionCount = 15) {
  return {
    [`users/${uid}/humor/calibration`]: {
      version: 1,
      completedCount: 15,
      stage: "complete",
      complete: true,
      ratedContentIds: [],
      coveredSlots: [],
      coveredDimensions: [],
      degradedCount: 0,
      completedAt: Timestamp.fromMillis(NOW - daysAgo * DAY),
    },
    [`users/${uid}/humor/summary`]: {
      vector: {sarcasm: 71.5, wordplay: 60.25, absurd: 38},
      confidence: 0.31,
      interactionCount,
      exploredCategories: ["sarcasm", "wordplay"],
      version: 1,
    },
  };
}

function seed(db, entries) {
  for (const [docPath, data] of Object.entries(entries)) {
    db._store.set(docPath, data);
  }
}

// The sequence is a draft (HUMOR_CORE_RELEASE.released === false), and a draft
// is handed out by the emulator process only. Everything below is about
// serving it, so the suite runs as the emulator; what a deployed backend does
// with a draft is pinned in productionSurface.test.cjs.
let savedEmulatorFlag;
beforeEach(() => {
  savedEmulatorFlag = process.env.FUNCTIONS_EMULATOR;
  process.env.FUNCTIONS_EMULATOR = "true";
});
afterEach(() => {
  if (savedEmulatorFlag === undefined) delete process.env.FUNCTIONS_EMULATOR;
  else process.env.FUNCTIONS_EMULATOR = savedEmulatorFlag;
});

describe("initial calibration", () => {
  it("serves a fresh member V1–V15 in canonical order, feed-safe", async () => {
    const db = await seededDb();
    const feed = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: NOW});
    assert.deepEqual(ids(feed.items), Vs(1, 15));
    assert.equal(feed.nextCursor, null);
    assert.equal(feed.catalogExhausted, false);
    assert.equal(feed.profileBuilding, true);
    assert.deepEqual(
      {
        completedCount: feed.calibration.completedCount,
        totalCount: feed.calibration.totalCount,
        complete: feed.calibration.complete,
        continuesTomorrow: feed.calibration.continuesTomorrow,
      },
      {completedCount: 0, totalCount: 15, complete: false, continuesTomorrow: false},
    );
    for (const item of feed.items) {
      assert.equal(item.humorVector, undefined);
      assert.equal(item.safetyFlags, undefined);
      assert.equal(item.calibration, undefined);
      assert.ok(item.media.downloadUrl);
    }
  });

  it("gives two fresh members the same fifteen ids in the same order", async () => {
    const db = await seededDb();
    const a = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: NOW});
    const b = await core.getHumorCoreFeedView({db, uid: "another-member-entirely", nowMs: at(9)});
    assert.deepEqual(ids(a.items), ids(b.items));
  });

  it("resumes at V8 after seven ratings — on a restart and on a second device", async () => {
    const db = await seededDb();
    await rateAll(db, "uA", Vs(1, 7));
    const feed = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: NOW + 3600_000});
    assert.deepEqual(ids(feed.items), Vs(8, 15));
    assert.equal(feed.calibration.completedCount, 7);
    assert.equal(feed.calibration.totalCount, 15);
    assert.deepEqual(coreDoc(db, "uA").today.contentIds, Vs(1, 15));
  });

  it("is complete only at the fifteenth rating", async () => {
    const db = await seededDb();
    await rateAll(db, "uA", Vs(1, 14));
    assert.equal(calibration(db, "uA").complete, false);
    assert.equal(coreDoc(db, "uA").initialCompletedAtMs, null);

    const last = await respond(db, "uA", V(15), "funny");
    assert.equal(last.onboardingCompletedNow, true);
    assert.equal(last.calibration.complete, true);
    assert.equal(last.calibration.completedCount, 15);
    assert.equal(calibration(db, "uA").complete, true);
    assert.equal(calibration(db, "uA").completedCount, 15);
    assert.equal(coreDoc(db, "uA").initialCompletedAtMs, NOW);
    assert.equal(isHumorCalibrationReady(calibration(db, "uA"), summary(db, "uA")), true);
  });

  it("closes the feed once the calibration is finished", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    for (const n of [1, 2, 30]) {
      const feed = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: at(n)});
      assert.deepEqual(feed.items, []);
      assert.equal(feed.catalogExhausted, true);
      assert.equal(feed.profileBuilding, false);
      assert.equal(feed.calibration.complete, true);
    }
  });
});

describe("daily five", () => {
  it("does not unlock the daily five on the day the calibration is finished", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: NOW + 3600_000});
    assert.equal(view.status, "locked");
    assert.equal(view.lockedReason, "starts_tomorrow");
    assert.deepEqual(view.items, []);
    await assert.rejects(dailyAnswer(db, "uA", V(16), "funny", 1), (error) => {
      assert.equal(error.reason, "slot-replaced");
      return true;
    });
    assert.equal(summary(db, "uA").interactionCount, 15);
  });

  it("locks a member whose calibration is still open", async () => {
    const db = await seededDb();
    await rateAll(db, "uA", Vs(1, 3));
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.equal(view.status, "locked");
    assert.equal(view.lockedReason, "calibration_incomplete");
  });

  it("gives exactly V16–V20 on the next logical day", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2)});
    assert.equal(view.status, "ready");
    assert.equal(view.dayId, dayId(2));
    assert.equal(view.total, HUMOR_CORE.dailyCount);
    assert.equal(view.total, 5);
    assert.deepEqual(ids(view.items), Vs(16, 20));
    assert.deepEqual(
      {answered: view.answeredCount, completed: view.completed, next: view.nextIndex},
      {answered: 0, completed: false, next: 0},
    );
  });

  it("keeps V21 out of today when V16 is rated, and resumes at V18 after two", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    const first = await dailyAnswer(db, "uA", V(16), "very_funny", 2);
    assert.deepEqual(
      {total: first.total, answered: first.answeredCount, next: first.nextIndex},
      {total: 5, answered: 1, next: 1},
    );
    await dailyAnswer(db, "uA", V(17), "funny", 2);

    const reopened = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2) + 7200_000});
    assert.deepEqual(ids(reopened.items), Vs(16, 20));
    assert.equal(reopened.nextIndex, 2);
    assert.equal(reopened.items[reopened.nextIndex].contentId, V(18));
    assert.deepEqual(
      reopened.answers.map((a) => [a.index, a.contentId, a.rating, a.skipped]),
      [
        [0, V(16), "very_funny", false],
        [1, V(17), "funny", false],
      ],
    );
  });

  it("completes on the fifth answer and offers nothing more that day", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    let last;
    for (const id of Vs(16, 20)) {
      last = await dailyAnswer(db, "uA", id, "funny", 2);
    }
    assert.deepEqual(
      {total: last.total, answered: last.answeredCount, completed: last.completed},
      {total: 5, answered: 5, completed: true},
    );
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2) + 60_000});
    assert.equal(view.completed, true);
    assert.deepEqual(ids(view.items), Vs(16, 20));
    await assert.rejects(dailyAnswer(db, "uA", V(21), "funny", 2), /slot-replaced/);
    assert.equal(summary(db, "uA").interactionCount, 20);

    const record = db._store.get(`users/uA/humorDaily/${dayId(2)}`);
    assert.equal(record.schema, core.HUMOR_CORE_DAY_SCHEMA);
    assert.equal(record.kind, "core");
    assert.deepEqual(record.contentIds, Vs(16, 20));
    assert.equal(record.completed, true);
  });

  it("gives V21–V25 the day after, and the same after three missed days", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    await rateAll(db, "uA", Vs(16, 20), 2);
    const next = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(3)});
    assert.deepEqual(ids(next.items), Vs(21, 25));

    const db2 = await seededDb();
    await calibrate(db2, "uB");
    await rateAll(db2, "uB", Vs(16, 20), 2);
    const late = await daily.getDailyHumorSetView({db: db2, uid: "uB", nowMs: at(6)});
    assert.deepEqual(ids(late.items), Vs(21, 25));
  });

  it("says so when the sequence is behind the member", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    let n = 2;
    for (let from = 16; from <= HUMOR_CORE_SEQUENCE.length; from += 5, n += 1) {
      await rateAll(db, "uA", Vs(from, Math.min(from + 4, HUMOR_CORE_SEQUENCE.length)), n);
    }
    assert.equal(summary(db, "uA").interactionCount, HUMOR_CORE_SEQUENCE.length);
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(n)});
    assert.equal(view.status, "locked");
    assert.equal(view.lockedReason, "sequence_complete");
  });
});

describe("server authority", () => {
  it("refuses tomorrow's entry, an earlier one and an arbitrary id — and learns nothing", async () => {
    const db = await seededDb();
    seed(db, {
      "humorContent/ext_giphy_abc": {
        type: "meme",
        language: "en",
        category: "silly",
        humorTags: [],
        humorVector: {silly: 0.9},
        media: {downloadUrl: "https://media.giphy.com/media/abc/giphy.webp"},
        safetyStatus: "approved",
        active: true,
        source: {type: "licensed_api", provider: "giphy"},
        sourceTrust: "provider",
      },
    });
    await calibrate(db, "uA");
    const before = plain(summary(db, "uA"));
    for (const id of [V(21), V(1), "ext_giphy_abc", "hc_gif_made_up"]) {
      await assert.rejects(respond(db, "uA", id, "very_funny", 2), (error) => {
        assert.ok(error instanceof core.HumorCoreRejected, id);
        assert.equal(error.reason, "not-in-set");
        return true;
      });
      await assert.rejects(dailyAnswer(db, "uA", id, "very_funny", 2), /slot-replaced/);
    }
    assert.deepEqual(plain(summary(db, "uA")), before);
    assert.equal(interaction(db, "uA", "ext_giphy_abc"), undefined);
    assert.equal(interaction(db, "uA", V(21)), undefined);
  });

  it("refuses a day the client names when it is not the server's day", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    for (const claimed of [dayId(1), dayId(3), dayId(40)]) {
      await assert.rejects(
        dailyAnswer(db, "uA", V(16), "funny", 2, {dayId: claimed}),
        (error) => {
          assert.equal(error.reason, "day-closed");
          return true;
        },
      );
    }
    assert.equal(summary(db, "uA").interactionCount, 15);
  });

  it("takes nothing from the request that could pick a position or a set", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    // Extra fields a tampering client might add are not even read.
    const parsed = daily.parseDailyResponseInput({
      dayId: dayId(2),
      contentId: V(16),
      rating: "funny",
      startIndex: 30,
      sequencePosition: 31,
      nextVideoIds: [V(30)],
      dayOverride: dayId(9),
    });
    assert.equal(parsed.ok, true);
    assert.deepEqual(Object.keys(parsed.value).sort(), [
      "contentId",
      "dayId",
      "dwellMs",
      "rating",
      "replayCount",
      "skipped",
    ]);
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2)});
    assert.deepEqual(ids(view.items), Vs(16, 20));
  });

  it("validates callable input: day id, content id, rating, and only media skips", () => {
    const ok = {dayId: TODAY, contentId: V(16), rating: "funny"};
    assert.equal(daily.parseDailyResponseInput(ok).ok, true);
    assert.equal(daily.parseDailyResponseInput({...ok, dayId: "tomorrow"}).field, "dayId");
    assert.equal(daily.parseDailyResponseInput({...ok, contentId: "a/b"}).field, "contentId");
    assert.equal(daily.parseDailyResponseInput({...ok, rating: "6"}).field, "rating");
    assert.equal(
      daily.parseDailyResponseInput({...ok, skipped: true, skipReason: "user"}).field,
      "skipReason",
    );
    assert.equal(
      daily.parseDailyResponseInput({...ok, skipped: true, skipReason: "media_failed"}).ok,
      true,
    );
  });

  it("honours the test clock only inside the emulator", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    seed(db, {"devClock/humorDaily": {dayId: dayId(2)}});
    // A deployed backend never reads the override: it is still today there.
    delete process.env.FUNCTIONS_EMULATOR;
    assert.equal(await daily.resolveDailyToday(db, NOW), TODAY);
    const locked = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.equal(locked.dayId, TODAY);
    assert.equal(locked.lockedReason, "starts_tomorrow");

    process.env.FUNCTIONS_EMULATOR = "true";
    assert.equal(await daily.resolveDailyToday(db, NOW), dayId(2));
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.equal(view.dayId, dayId(2));
    assert.deepEqual(ids(view.items), Vs(16, 20));
    seed(db, {"devClock/humorDaily": {dayId: "not-a-day"}});
    assert.equal(await daily.resolveDailyToday(db, NOW), TODAY);
  });

  it("shares progress between devices: what one answered, the other sees", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    await dailyAnswer(db, "uA", V(16), "funny", 2); // device A
    const deviceB = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2) + 5_000});
    assert.equal(deviceB.answeredCount, 1);
    assert.equal(deviceB.nextIndex, 1);
    const fromB = await dailyAnswer(db, "uA", V(17), "neutral", 2);
    assert.equal(fromB.answeredCount, 2);
    const deviceA = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2) + 9_000});
    assert.equal(deviceA.nextIndex, 2);
  });
});

describe("learning", () => {
  it("teaches the lifetime profile from V1, and the same profile from V16", async () => {
    const db = await seededDb();
    const first = await respond(db, "uA", V(1), "very_funny");
    assert.equal(first.profile.interactionCount, 1);
    const afterV1 = structuredClone(summary(db, "uA"));
    assert.ok(afterV1.vector.sarcasm > 50, "V1 is a sarcasm clip");
    assert.ok(interaction(db, "uA", V(1)).appliedDelta);

    await rateAll(db, "uA", Vs(2, 15));
    assert.equal(summary(db, "uA").interactionCount, 15);
    const confidenceAt15 = summary(db, "uA").confidence;

    await dailyAnswer(db, "uA", V(16), "very_funny", 2);
    assert.equal(summary(db, "uA").interactionCount, 16);
    assert.ok(summary(db, "uA").confidence > confidenceAt15, "evidence keeps accumulating");
    assert.ok(summary(db, "uA").confidence < 1, "fifteen ratings are not perfect knowledge");
    assert.ok(interaction(db, "uA", V(16)).appliedDelta);
  });

  it("counts a response once, even on double taps and retries", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    const [r1, r2] = await Promise.all([
      dailyAnswer(db, "uA", V(16), "very_funny", 2),
      dailyAnswer(db, "uA", V(16), "very_funny", 2),
    ]);
    const r3 = await dailyAnswer(db, "uA", V(16), "very_funny", 2);
    assert.equal(summary(db, "uA").interactionCount, 16);
    assert.deepEqual([r1.answeredCount, r2.answeredCount, r3.answeredCount], [1, 1, 1]);
    assert.equal(r3.alreadyAnswered, true);
  });

  it("replaces the contribution when today's rating changes, instead of adding one", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    const before = structuredClone(summary(db, "uA"));
    await dailyAnswer(db, "uA", V(16), "very_funny", 2);
    const liked = structuredClone(summary(db, "uA"));
    await dailyAnswer(db, "uA", V(16), "not_at_all", 2);
    const disliked = summary(db, "uA");
    assert.equal(disliked.interactionCount, before.interactionCount + 1);
    assert.ok(liked.vector.wordplay > before.vector.wordplay);
    assert.ok(disliked.vector.wordplay < before.vector.wordplay);
    assert.equal(coreDoc(db, "uA").answers[V(16)].rating, "not_at_all");
  });

  it("never turns a media failure into evidence", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    const before = plain(summary(db, "uA"));
    const result = await dailyAnswer(db, "uA", V(16), null, 2, {skipped: true});
    assert.equal(result.answeredCount, 1);
    assert.deepEqual(plain(summary(db, "uA")), before);
    assert.equal(coreDoc(db, "uA").answers[V(16)], undefined);
    assert.deepEqual(coreDoc(db, "uA").mediaFailures[V(16)].days, [dayId(2)]);
    assert.equal(interaction(db, "uA", V(16)).rating, null);
    assert.equal(interaction(db, "uA", V(16)).skipReason, "media_failed");

    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2)});
    assert.deepEqual(view.answers, [{index: 0, contentId: V(16), rating: null, skipped: true}]);
    // The entry is asked again tomorrow, and a real rating then counts as its first.
    const tomorrow = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(3)});
    assert.equal(tomorrow.items[0].contentId, V(16));
    await dailyAnswer(db, "uA", V(16), "funny", 3);
    assert.equal(summary(db, "uA").interactionCount, 16);
  });

  it("keeps a recorded rating when a media skip arrives for it", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    await dailyAnswer(db, "uA", V(16), "funny", 2);
    const skip = await dailyAnswer(db, "uA", V(16), null, 2, {skipped: true});
    assert.equal(skip.alreadyAnswered, true);
    assert.equal(coreDoc(db, "uA").answers[V(16)].rating, "funny");
    assert.equal(interaction(db, "uA", V(16)).rating, "funny");
  });

  it("lets two members who answer differently diverge, through the existing engine", async () => {
    const db = await seededDb();
    const loves = new Set(["sarcasm", "dark", "dry"]);
    const catalog = new Map(
      HUMOR_CORE_SEQUENCE.map((entry) => [entry.id, db._store.get(`humorContent/${entry.id}`)]),
    );
    await calibrate(db, "uA", 1, (id) => (loves.has(catalog.get(id).category) ? "very_funny" : "not_at_all"));
    await calibrate(db, "uB", 1, (id) => (loves.has(catalog.get(id).category) ? "not_at_all" : "very_funny"));
    const a = summary(db, "uA");
    const b = summary(db, "uB");
    assert.ok(a.vector.sarcasm > 60 && b.vector.sarcasm < 40);
    assert.ok(a.vector.silly < 40 && b.vector.silly > 60);

    const opposite = humorScoreForPair(a, b, {readyA: true, readyB: true});
    assert.equal(opposite.available, true);

    await calibrate(db, "uC", 1, (id) => (loves.has(catalog.get(id).category) ? "very_funny" : "not_at_all"));
    const same = humorScoreForPair(a, summary(db, "uC"), {readyA: true, readyB: true});
    assert.ok(same.score > opposite.score, `${same.score} vs ${opposite.score}`);
  });
});

describe("media failure during the initial calibration", () => {
  it("pauses instead of completing, and says so", async () => {
    const db = await seededDb();
    await respond(db, "uA", V(7), null, 1, {mediaFailed: true});
    await rateAll(db, "uA", [...Vs(1, 6), ...Vs(8, 15)]);
    assert.equal(calibration(db, "uA").complete, false);

    const paused = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: NOW + 60_000});
    assert.deepEqual(paused.items, []);
    assert.equal(paused.calibration.complete, false);
    assert.equal(paused.calibration.continuesTomorrow, true);
    assert.equal(paused.calibration.completedCount, 14);
    assert.equal(paused.catalogEmpty, false);

    const tomorrow = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: at(2)});
    assert.deepEqual(ids(tomorrow.items), [V(7)]);
    const done = await respond(db, "uA", V(7), "funny", 2);
    assert.equal(done.onboardingCompletedNow, true);
    assert.equal(calibration(db, "uA").complete, true);
  });

  it("finishes the calibration when the same clip fails on a second day — downstream readers see a ready member", async () => {
    const db = await seededDb();
    await respond(db, "uA", V(7), null, 1, {mediaFailed: true});
    await rateAll(db, "uA", [...Vs(1, 6), ...Vs(8, 15)]);
    const second = await respond(db, "uA", V(7), null, 2, {mediaFailed: true});
    assert.equal(second.onboardingCompletedNow, true);
    assert.equal(summary(db, "uA").interactionCount, 14);
    assert.equal(coreDoc(db, "uA").waived[V(7)].reason, "media_failed");
    assert.equal(calibration(db, "uA").complete, true);
    assert.equal(calibration(db, "uA").completedBy, "core");
    assert.equal(isHumorCalibrationReady(calibration(db, "uA"), summary(db, "uA")), true);
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(3)});
    assert.deepEqual(ids(view.items), Vs(16, 20));
  });
});

describe("content that cannot be served", () => {
  it("skips a taken-down entry instead of swapping something in", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    db._store.set(`humorContent/${V(17)}`, {
      ...db._store.get(`humorContent/${V(17)}`),
      safetyStatus: "rejected",
    });
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2)});
    assert.deepEqual(ids(view.items), [V(16), V(18), V(19), V(20), V(21)]);
    await assert.rejects(dailyAnswer(db, "uA", V(17), "funny", 2), /slot-replaced/);
  });

  it("shrinks a frozen day when one of its entries is taken down", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    await dailyAnswer(db, "uA", V(16), "funny", 2);
    db._store.set(`humorContent/${V(18)}`, {...db._store.get(`humorContent/${V(18)}`), active: false});
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2)});
    assert.deepEqual(ids(view.items), [V(16), V(17), V(19), V(20)]);
    assert.equal(view.total, 4);
  });

  it("never serves a provider-synced item, however approved it is", async () => {
    const db = await seededDb();
    seed(db, {
      "humorContent/ext_giphy_zz9": {
        type: "meme",
        language: "tr",
        category: "meme",
        humorTags: [],
        humorVector: {meme: 0.9},
        media: {downloadUrl: "https://media.giphy.com/media/zz9/giphy.webp"},
        safetyStatus: "approved",
        active: true,
        source: {type: "licensed_api", provider: "giphy"},
        sourceTrust: "verified_provider",
      },
    });
    await calibrate(db, "uA");
    const seen = new Set();
    for (let n = 1; n <= 8; n += 1) {
      const feed = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: at(n)});
      const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(n)});
      for (const item of [...feed.items, ...view.items]) seen.add(item.contentId);
      if (view.status === "ready") await rateAll(db, "uA", ids(view.items), n);
    }
    assert.ok(seen.size > 0);
    for (const id of seen) assert.ok(id.startsWith("hc_gif_"), id);
  });

  it("reports an empty catalogue as empty, not as a finished calibration", async () => {
    const db = createFakeFirestore();
    const feed = await core.getHumorCoreFeedView({db, uid: "uA", nowMs: NOW});
    assert.deepEqual(feed.items, []);
    assert.equal(feed.catalogEmpty, true);
    assert.equal(feed.calibration.complete, false);
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: NOW});
    assert.equal(view.lockedReason, "calibration_incomplete");
  });

  it("waives an entry the member reported, so it does not hold their day open", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    await core.waiveReportedHumorCoreItem({db, uid: "uA", nowMs: at(2), contentId: V(16)});
    assert.equal(coreDoc(db, "uA").waived[V(16)].reason, "reported");
    assert.equal(summary(db, "uA").interactionCount, 15);
    const view = await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(2)});
    assert.equal(view.nextIndex, 1);
    // Reporting something that is not in front of the member changes nothing.
    await core.waiveReportedHumorCoreItem({db, uid: "uA", nowMs: at(2), contentId: V(30)});
    await core.waiveReportedHumorCoreItem({db, uid: "uA", nowMs: at(2), contentId: "ext_giphy_x"});
    assert.equal(coreDoc(db, "uA").waived[V(30)], undefined);
  });
});

describe("members from before the Core sequence", () => {
  it("keeps the profile, the interactions and the old daily days exactly as they were", async () => {
    const db = await seededDb();
    const legacy = {
      ...legacyCalibrated("uL", 12, 42),
      [`users/uL/humorInteractions/${V(2)}`]: {
        contentId: V(2),
        rating: "very_funny",
        appliedDelta: {absurd: 4.5},
        appliedStep: 0.2,
        skipped: false,
      },
      "users/uL/humorInteractions/ext_giphy_old": {contentId: "ext_giphy_old", rating: "funny", skipped: false},
      [`users/uL/humorDaily/${dayId(-2)}`]: {
        dayId: dayId(-2),
        setVersion: 1,
        total: 10,
        answers: {"0": {contentId: "ext_giphy_old", rating: "funny", skipped: false}},
        answeredCount: 10,
        completed: true,
      },
    };
    seed(db, legacy);
    const before = plain(legacy);

    const view = await daily.getDailyHumorSetView({db, uid: "uL", nowMs: NOW});
    assert.equal(view.status, "ready");
    assert.equal(view.total, 5);
    // Five a day from V1; the entry they already rated is not asked again.
    assert.deepEqual(ids(view.items), [V(1), V(3), V(4), V(5), V(6)]);

    for (const [docPath, data] of Object.entries(before)) {
      assert.deepEqual(plain(db._store.get(docPath)), data, docPath);
    }
    const state = coreDoc(db, "uL");
    assert.deepEqual(
      {...state.migration, atMs: 0},
      {
        from: "adaptive-v1",
        legacyComplete: true,
        legacyCompletedCount: 15,
        importedRatings: 1,
        importedWaivers: 0,
        atMs: 0,
      },
    );
    assert.equal(state.answers[V(2)].source, "legacy");
    assert.equal(state.initialCompletedAtMs, NOW - 12 * DAY);

    const feed = await core.getHumorCoreFeedView({db, uid: "uL", nowMs: NOW});
    assert.deepEqual(feed.items, []);
    assert.equal(feed.calibration.complete, true);
    assert.equal(feed.calibration.completedCount, 15);
  });

  it("goes on learning on top of the evidence they already had", async () => {
    const db = await seededDb();
    seed(db, legacyCalibrated("uL", 12, 42));
    const confidenceBefore = summary(db, "uL").confidence;
    await dailyAnswer(db, "uL", V(1), "very_funny", 1);
    const after = summary(db, "uL");
    assert.equal(after.interactionCount, 43);
    assert.ok(after.vector.sarcasm > 71.5);
    assert.equal(after.vector.absurd, 38);
    assert.ok(after.confidence >= confidenceBefore);
    assert.equal(calibration(db, "uL").complete, true);
  });

  it("is deterministic: asked twice, or by two requests at once, the migration is the same", async () => {
    const db = await seededDb();
    seed(db, legacyCalibrated("uL", 12));
    const [a, b] = await Promise.all([
      daily.getDailyHumorSetView({db, uid: "uL", nowMs: NOW}),
      daily.getDailyHumorSetView({db, uid: "uL", nowMs: NOW}),
    ]);
    const c = await daily.getDailyHumorSetView({db, uid: "uL", nowMs: NOW + 1000});
    assert.deepEqual(ids(a.items), ids(b.items));
    assert.deepEqual(ids(a.items), ids(c.items));
    assert.deepEqual(ids(a.items), Vs(1, 5));
  });

  it("starts tomorrow for a member who finished the old calibration today", async () => {
    const db = await seededDb();
    seed(db, legacyCalibrated("uL", 0));
    seed(db, {
      "users/uL/humor/calibration": {
        ...db._store.get("users/uL/humor/calibration"),
        completedAt: Timestamp.fromMillis(NOW - 600_000),
      },
    });
    const today = await daily.getDailyHumorSetView({db, uid: "uL", nowMs: NOW});
    assert.equal(today.lockedReason, "starts_tomorrow");
    const tomorrow = await daily.getDailyHumorSetView({db, uid: "uL", nowMs: at(2)});
    assert.deepEqual(ids(tomorrow.items), Vs(1, 5));
  });

  it("starts tomorrow for a member who already did the old daily set today", async () => {
    const db = await seededDb();
    seed(db, {
      ...legacyCalibrated("uL", 20),
      [`users/uL/humorDaily/${TODAY}`]: {dayId: TODAY, total: 10, answeredCount: 4, completed: false},
    });
    const today = await daily.getDailyHumorSetView({db, uid: "uL", nowMs: NOW});
    assert.equal(today.status, "locked");
    assert.equal(today.lockedReason, "starts_tomorrow");
    assert.equal(db._store.get(`users/uL/humorDaily/${TODAY}`).answeredCount, 4);
  });

  it("keeps a pre-calibration ready profile ready after its first Core rating", async () => {
    const db = await seededDb();
    seed(db, {
      "users/uOld/humor/summary": {
        vector: {meme: 66},
        confidence: 0.4,
        interactionCount: 20,
        exploredCategories: [],
        version: 1,
      },
    });
    assert.equal(isHumorCalibrationReady(undefined, summary(db, "uOld")), true);
    const view = await daily.getDailyHumorSetView({db, uid: "uOld", nowMs: NOW});
    assert.deepEqual(ids(view.items), Vs(1, 5));
    await dailyAnswer(db, "uOld", V(1), "funny", 1);
    assert.equal(isHumorCalibrationReady(calibration(db, "uOld"), summary(db, "uOld")), true);
    assert.equal(summary(db, "uOld").interactionCount, 21);
  });

  it("lets a member in the middle of the old calibration continue with V1–V15", async () => {
    const db = await seededDb();
    seed(db, {
      "users/uMid/humor/calibration": {
        version: 1,
        completedCount: 9,
        stage: "adaptive",
        complete: false,
        ratedContentIds: [V(1), V(31)],
        coveredSlots: ["anchor_wit"],
        coveredDimensions: ["sarcasm"],
        degradedCount: 0,
      },
      "users/uMid/humor/summary": {
        vector: {sarcasm: 64},
        confidence: 0.2,
        interactionCount: 9,
        exploredCategories: ["sarcasm"],
        version: 1,
      },
      [`users/uMid/humorInteractions/${V(1)}`]: {contentId: V(1), rating: "funny", skipped: false},
      [`users/uMid/humorInteractions/${V(31)}`]: {contentId: V(31), rating: "funny", skipped: false},
    });
    const feed = await core.getHumorCoreFeedView({db, uid: "uMid", nowMs: NOW});
    assert.deepEqual(ids(feed.items), Vs(2, 15));
    assert.equal(feed.calibration.completedCount, 1);
    assert.equal(feed.calibration.totalCount, 15);
    assert.equal(summary(db, "uMid").interactionCount, 9);

    await rateAll(db, "uMid", Vs(2, 15));
    assert.equal(calibration(db, "uMid").complete, true);
    assert.equal(summary(db, "uMid").interactionCount, 23);
    // V31, rated before, is not asked again later.
    assert.equal(coreDoc(db, "uMid").answers[V(31)].source, "legacy");
  });
});

describe("profile view", () => {
  it("reports calibration progress from the Core state", async () => {
    const db = await seededDb();
    await rateAll(db, "uA", Vs(1, 4));
    const view = await core.getHumorCoreProfileView({db, uid: "uA", nowMs: NOW, detailed: false});
    assert.equal(view.profileBuilding, true);
    assert.deepEqual(
      {done: view.calibration.completedCount, total: view.calibration.totalCount, complete: view.calibration.complete},
      {done: 4, total: 15, complete: false},
    );
    assert.equal(view.vector, undefined);
    const detailed = await core.getHumorCoreProfileView({db, uid: "uA", nowMs: NOW, detailed: true});
    assert.ok(detailed.vector);
  });
});

describe("sequence report", () => {
  it("lists every position with the state of its content", async () => {
    const db = await seededDb();
    const report = await core.buildHumorCoreSequenceReport(db);
    assert.equal(report.total, HUMOR_CORE_SEQUENCE.length);
    assert.equal(report.servableCount, HUMOR_CORE_SEQUENCE.length);
    assert.equal(report.healthy, true);
    assert.deepEqual([report.onboardingCount, report.dailyCount], [15, 5]);
    assert.equal(report.released, false);
    const first = report.items[0];
    assert.deepEqual(
      {position: first.position, contentId: first.contentId, onboarding: first.onboarding, servable: first.servable},
      {position: 1, contentId: V(1), onboarding: true, servable: true},
    );
    assert.equal(first.category, "sarcasm");
    assert.equal(first.provider, "giphy");
    assert.match(first.topDimensions[0], /^sarcasm 0\.88$/);
    assert.equal(report.items[15].onboarding, false);
  });

  it("names the entries a member cannot be given", async () => {
    const db = await seededDb();
    db._store.delete(`humorContent/${V(3)}`);
    db._store.set(`humorContent/${V(9)}`, {...db._store.get(`humorContent/${V(9)}`), safetyStatus: "needs_review"});
    const report = await core.buildHumorCoreSequenceReport(db);
    assert.equal(report.healthy, false);
    assert.deepEqual(report.warnings, [
      `V3 ${V(3)}: content document missing`,
      `V9 ${V(9)}: content needs_review`,
    ]);
  });
});

describe("no daily-ten assumption is left", () => {
  it("has no daily set size in the humor configuration", () => {
    assert.equal(DAILY_HUMOR_CONFIG.setSize, undefined);
    assert.equal(HUMOR_CORE.dailyCount, 5);
  });

  it("has no selector, global manifest or publish path in the humor backend", () => {
    const dir = path.join(__dirname, "..", "src", "humor");
    for (const file of fs.readdirSync(dir).filter((name) => name.endsWith(".ts"))) {
      const source = fs.readFileSync(path.join(dir, file), "utf8");
      for (const gone of [
        "selectDailySet",
        "ensureDailySet",
        "repairDailySlot",
        "selectCalibrationItems",
        "selectAdaptiveDimensions",
        "rotatingPick",
        "setSize",
      ]) {
        assert.ok(!source.includes(gone), `${file} still mentions ${gone}`);
      }
    }
    const index = fs.readFileSync(path.join(__dirname, "..", "src", "index.ts"), "utf8");
    assert.ok(!index.includes("publishDailyHumorSet"));
    assert.ok(!index.includes("repairDailyHumorSlot"));
  });

  it("never writes the old global daily manifest", async () => {
    const db = await seededDb();
    await calibrate(db, "uA");
    await rateAll(db, "uA", Vs(16, 20), 2);
    await daily.getDailyHumorSetView({db, uid: "uA", nowMs: at(3)});
    for (const key of db._store.keys()) {
      assert.ok(!key.startsWith("humorDailySets/"), key);
    }
  });
});
