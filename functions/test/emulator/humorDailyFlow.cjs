/**
 * Daily Humor Evolution against the real Firestore emulator.
 *
 * The unit suite (`functions/test/humorDaily.test.cjs`) proves the rules with
 * an in-memory double, which has no transaction contention. This runs the
 * same service through real Firestore transactions: concurrent first
 * requests publishing one manifest, concurrent double taps counting once,
 * resume, completion and the emulator-only next-day clock.
 *
 * Run through `npm --prefix functions run test:emulator:humor` (free ports,
 * throwaway emulator, demo- project).
 */
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST is not set — refusing to run.");
  process.exit(2);
}

const {seedCalibrationCatalog} = require("../../lib/humor/calibrationCatalog.js");
const service = require("../../lib/humor/dailyService.js");
const {canonicalDayId, shiftDayId} = require("../../lib/humor/daily.js");

initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-humor-qa"});
const db = getFirestore();

const NOW = Date.now();
const TODAY = canonicalDayId(NOW);
const DAY = 24 * 60 * 60 * 1000;
const steps = [];
const step = (name, fn) => steps.push([name, fn]);

async function calibrate(uid, completedAtMs, interactionCount = 15) {
  await db.doc(`users/${uid}/humor/calibration`).set({
    version: 1,
    completedCount: 15,
    complete: true,
    completedAt: Timestamp.fromMillis(completedAtMs),
  });
  await db.doc(`users/${uid}/humor/summary`).set({
    vector: {sarcasm: 65, wordplay: 60},
    confidence: 0.4,
    interactionCount,
    exploredCategories: [],
    version: 1,
  });
}

function respond(uid, dayId, contentId, rating, skipped = false) {
  return service.submitDailyHumorResponse({
    db,
    uid,
    nowMs: NOW,
    response: {dayId, contentId, rating: skipped ? null : rating, skipped, dwellMs: 900, replayCount: 0},
  });
}

let ids = [];

step("seed the curated catalogue and three members", async () => {
  await seedCalibrationCatalog(db);
  await calibrate("qa_daily_a", NOW - 2 * DAY);
  await calibrate("qa_daily_b", NOW - 9 * DAY, 40);
  await calibrate("qa_daily_fresh", NOW - 60_000);
});

step("concurrent first requests publish exactly one manifest", async () => {
  const results = await Promise.all(
    Array.from({length: 8}, () =>
      service.ensureDailySet({db, dayId: TODAY, nowMs: NOW, publishedBy: "flow"}),
    ),
  );
  assert.equal(results.filter((r) => r.created).length, 1);
  assert.equal(new Set(results.map((r) => r.manifest.contentIds.join(","))).size, 1);
  ids = results[0].manifest.contentIds;
  assert.equal(ids.length, 10);
});

step("two members see the same ten ids in the same order; a fresh member is locked", async () => {
  const [a, b, fresh] = await Promise.all([
    service.getDailyHumorSetView({db, uid: "qa_daily_a", nowMs: NOW}),
    service.getDailyHumorSetView({db, uid: "qa_daily_b", nowMs: NOW}),
    service.getDailyHumorSetView({db, uid: "qa_daily_fresh", nowMs: NOW}),
  ]);
  assert.deepEqual(a.items.map((i) => i.contentId), ids);
  assert.deepEqual(b.items.map((i) => i.contentId), ids);
  assert.deepEqual([fresh.status, fresh.lockedReason], ["locked", "starts_tomorrow"]);
  console.log(`    day ${TODAY}: ${ids.join(" ")}`);
});

step("a concurrent double tap counts once in progress and in the profile", async () => {
  const before = (await db.doc("users/qa_daily_a/humor/summary").get()).data().interactionCount;
  const results = await Promise.all([
    respond("qa_daily_a", TODAY, ids[0], "very_funny"),
    respond("qa_daily_a", TODAY, ids[0], "very_funny"),
    respond("qa_daily_a", TODAY, ids[0], "very_funny"),
  ]);
  assert.ok(results.every((r) => r.answeredCount === 1));
  const after = (await db.doc("users/qa_daily_a/humor/summary").get()).data().interactionCount;
  assert.equal(after, before + 1);
});

step("resume at 3/10 and 9/10 returns the next unanswered item", async () => {
  await respond("qa_daily_a", TODAY, ids[1], "funny");
  await respond("qa_daily_a", TODAY, ids[2], "not_funny");
  const at3 = await service.getDailyHumorSetView({db, uid: "qa_daily_a", nowMs: NOW});
  assert.deepEqual([at3.answeredCount, at3.nextIndex, at3.items[at3.nextIndex].contentId], [3, 3, ids[3]]);
  for (let i = 3; i < 9; i++) await respond("qa_daily_a", TODAY, ids[i], i % 2 ? "funny" : "neutral");
  const at9 = await service.getDailyHumorSetView({db, uid: "qa_daily_a", nowMs: NOW});
  assert.deepEqual([at9.answeredCount, at9.nextIndex, at9.items[9].contentId], [9, 9, ids[9]]);
});

step("the tenth answer completes the day, once", async () => {
  const done = await respond("qa_daily_a", TODAY, ids[9], "funny");
  assert.deepEqual([done.answeredCount, done.completed, done.nextIndex], [10, true, 10]);
  const stored = (await db.doc(`users/qa_daily_a/humorDaily/${TODAY}`).get()).data();
  assert.equal(stored.completed, true);
  assert.ok(stored.completedAt instanceof Timestamp);
  const again = await respond("qa_daily_a", TODAY, ids[9], "funny");
  assert.equal(again.alreadyAnswered, true);
  const b = await service.getDailyHumorSetView({db, uid: "qa_daily_b", nowMs: NOW});
  assert.equal(b.answeredCount, 0);
});

step("the emulator clock moves to the next day: a new set, fresh progress", async () => {
  process.env.FUNCTIONS_EMULATOR = "true";
  const tomorrow = shiftDayId(TODAY, 1);
  await db.doc(service.DAILY_DEV_CLOCK_DOC).set({dayId: tomorrow});
  try {
    const next = await service.getDailyHumorSetView({db, uid: "qa_daily_a", nowMs: NOW});
    assert.deepEqual([next.dayId, next.status, next.answeredCount], [tomorrow, "ready", 0]);
    const overlap = next.items.filter((i) => ids.includes(i.contentId));
    assert.equal(overlap.length, 0);
    const fresh = await service.getDailyHumorSetView({db, uid: "qa_daily_fresh", nowMs: NOW});
    assert.equal(fresh.status, "ready");
    assert.deepEqual(
      fresh.items.map((i) => i.contentId),
      next.items.map((i) => i.contentId),
    );
    await assert.rejects(respond("qa_daily_a", TODAY, ids[0], "funny"), (e) => e.reason === "day-closed");
  } finally {
    await db.doc(service.DAILY_DEV_CLOCK_DOC).delete();
    delete process.env.FUNCTIONS_EMULATOR;
  }
});

(async () => {
  let failed = 0;
  for (const [name, fn] of steps) {
    try {
      await fn();
      console.log(`  ok   ${name}`);
    } catch (error) {
      failed += 1;
      console.error(`  FAIL ${name}\n       ${error && error.stack ? error.stack : error}`);
    }
  }
  console.log(`\n${steps.length - failed}/${steps.length} daily humor steps passed`);
  process.exit(failed === 0 ? 0 : 1);
})();
