/**
 * The Humor Core sequence against the real Firestore emulator.
 *
 * The unit suites (`humorCoreSchedule.test.cjs`, `humorCoreService.test.cjs`)
 * prove the rules with an in-memory double, which has no transaction
 * contention and no real merge semantics. This runs the same service through
 * actual Firestore: seeding, the fixed first fifteen, concurrent taps, the
 * day freeze, the emulator-only clock, five a day, missed days, media
 * failures and a member from before the sequence.
 *
 * Deliberately lives in a subdirectory so the emulator-free `npm test` does
 * not pick it up. Run through `npm --prefix functions run test:emulator:humor`
 * (free ports, throwaway emulator, demo- project).
 */
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST is not set — refusing to run.");
  process.exit(2);
}

const {
  CALIBRATION_TOTAL,
  HUMOR_CALIBRATION_VERSION,
  parseCalibrationState,
} = require("../../lib/humor/calibration.js");
const {
  INTERNAL_HUMOR_SEED,
  upsertHumorContentDoc,
  listCalibrationPool,
} = require("../../lib/humor/contentRepository.js");
const {
  TEXT_JOKE_CONTENT_IDS,
  seedCalibrationCatalog,
} = require("../../lib/humor/calibrationCatalog.js");
const {DAILY_DEV_CLOCK_DOC} = require("../../lib/humor/clock.js");
const {isHumorCalibrationReady} = require("../../lib/humor/compatibility.js");
const {HUMOR_CORE, HUMOR_CORE_SEQUENCE} = require("../../lib/humor/coreSequence.js");
const core = require("../../lib/humor/coreService.js");
const daily = require("../../lib/humor/dailyService.js");
const {canonicalDayId, shiftDayId} = require("../../lib/humor/daily.js");
const {submitHumorFeedbackTx} = require("../../lib/humor/feedback.js");

initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-humor-qa"});
const db = getFirestore();

// This flow calls the compiled service in its own process, standing in for
// the Functions emulator. The Core sequence is a draft, and a draft is handed
// out by the emulator process only (`isHumorCoreServed`), so the whole flow
// runs as that process. The dev clock is therefore honoured from the first
// step; the run starts by clearing any override an earlier run left behind.
process.env.FUNCTIONS_EMULATOR = "true";

const NOW = Date.now();
const TODAY = canonicalDayId(NOW);
const DAY = 24 * 60 * 60 * 1000;
const UID = "qa_core_user";

const V = (n) => HUMOR_CORE_SEQUENCE[n - 1].id;
const Vs = (from, to) => Array.from({length: to - from + 1}, (_, i) => V(from + i));
const ids = (items) => items.map((item) => item.contentId);
const read = async (path) => (await db.doc(path).get()).data();

const steps = [];
const step = (name, fn) => steps.push([name, fn]);

/** Moves the emulator-only product day, exactly as tool/humorDailyDev.cjs does. */
async function setDay(offset) {
  process.env.FUNCTIONS_EMULATOR = "true";
  await db.doc(DAILY_DEV_CLOCK_DOC).set({dayId: shiftDayId(TODAY, offset)});
  return shiftDayId(TODAY, offset);
}

function respond(uid, contentId, rating, extra = {}) {
  return core.submitHumorCoreResponse({
    db,
    uid,
    nowMs: NOW,
    contentId,
    rating: extra.mediaFailed ? null : rating,
    mediaFailed: extra.mediaFailed === true,
    dwellMs: 900,
    replayCount: 0,
  });
}

function dailyAnswer(uid, dayId, contentId, rating) {
  return daily.submitDailyHumorResponse({
    db,
    uid,
    nowMs: NOW,
    response: {dayId, contentId, rating, skipped: false, dwellMs: 900, replayCount: 0},
  });
}

step("re-seeding replaces a stale item with exactly the curated clip", async () => {
  // Real Firestore merge semantics: `set(..., {merge: true})` deep-merges
  // maps, so only explicit values replace what an older seed left behind.
  const seed = INTERNAL_HUMOR_SEED.find((i) => i.calibration.slot === "anchor_everyday");
  await db.doc(`humorContent/${seed.contentId}`).set({
    contentId: seed.contentId,
    type: "text",
    language: "tr",
    category: "situational",
    media: {
      downloadUrl: "https://picsum.photos/seed/mevora-tr-15/1080/1920",
      thumbUrl: "https://picsum.photos/seed/mevora-tr-15/540/960",
      aspectRatio: 0.5625,
      textBody: "Markete süt için girdim, üç poşetle çıktım. Süt yok.",
    },
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0, ratingSum: 0},
  });
  await upsertHumorContentDoc(db, {...seed, safetyStatus: "approved", active: true});
  const stored = await read(`humorContent/${seed.contentId}`);
  assert.equal(stored.type, "meme");
  assert.equal(stored.media.downloadUrl, seed.media.downloadUrl);
  assert.equal(stored.media.textBody, null, "no caption survives on a clip");
  assert.deepEqual(stored.attribution, seed.attribution);
  assert.equal(stored.sourceTrust, "curated");
  assert.equal(stored.stats.ratingSum, 0, "existing stats are kept, not reset");
  return "clip media and credit written, caption cleared, stats kept";
});

step("seed the curated catalogue; provider content stays out of it", async () => {
  const legacyId = TEXT_JOKE_CONTENT_IDS[0];
  await upsertHumorContentDoc(db, {
    contentId: legacyId,
    type: "text",
    language: "tr",
    category: "sarcasm",
    humorVector: {sarcasm: 0.88},
    media: {textBody: "Tabii, trafik yine benim yüzümden oluştu."},
    safetyStatus: "approved",
    active: true,
    calibration: {eligible: true, slot: "anchor_wit", version: HUMOR_CALIBRATION_VERSION},
  });
  const seeded = await seedCalibrationCatalog(db);
  assert.equal(seeded.kind, "curated_giphy");
  assert.equal(seeded.written, INTERNAL_HUMOR_SEED.length);
  assert.deepEqual(seeded.retiredIds, [legacyId]);

  // Provider-shaped content: approved and servable, but never curated.
  await db.doc("humorContent/ext_giphy_untrusted").set({
    contentId: "ext_giphy_untrusted",
    type: "video",
    language: "tr",
    category: "meme",
    humorTags: ["meme"],
    humorVector: {meme: 0.9},
    media: {downloadUrl: "https://media.giphy.com/x.mp4"},
    safetyStatus: "approved",
    safetyFlags: {},
    source: {type: "licensed_api", provider: "giphy", licenseRef: null},
    calibrationSlot: "anchor_meme",
    active: true,
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
  });
  const pool = await listCalibrationPool(db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });
  assert.equal(pool.some((item) => item.contentId === "ext_giphy_untrusted"), false);

  const report = await core.buildHumorCoreSequenceReport(db);
  assert.equal(report.healthy, true, [...report.problems, ...report.warnings].join("; "));
  assert.equal(report.servableCount, HUMOR_CORE_SEQUENCE.length);
  return `${report.servableCount}/${report.total} sequence entries servable`;
});

step("a fresh member gets V1–V15 in canonical order, feed-safe", async () => {
  const feed = await core.getHumorCoreFeedView({db, uid: UID, nowMs: NOW});
  assert.deepEqual(ids(feed.items), Vs(1, 15));
  assert.equal(feed.calibration.completedCount, 0);
  assert.equal(feed.calibration.totalCount, HUMOR_CORE.onboardingCount);
  assert.equal(feed.nextCursor, null);
  for (const item of feed.items) {
    assert.equal("calibrationSlot" in item, false);
    assert.equal("humorVector" in item, false);
    assert.equal("safetyFlags" in item, false);
  }
  return ids(feed.items).slice(0, 3).join(" ") + " …";
});

step("a second fresh member gets the same fifteen ids in the same order", async () => {
  const feed = await core.getHumorCoreFeedView({db, uid: "qa_core_user_two", nowMs: NOW});
  assert.deepEqual(ids(feed.items), Vs(1, 15));
});

step("rapid double tap on one card counts exactly once", async () => {
  const results = await Promise.allSettled([
    respond(UID, V(1), "very_funny"),
    respond(UID, V(1), "very_funny"),
    respond(UID, V(1), "very_funny"),
  ]);
  const rejected = results.filter((r) => r.status === "rejected");
  assert.equal(rejected.length, 0, rejected.map((r) => String(r.reason)).join("; "));
  assert.equal((await read(`users/${UID}/humor/summary`)).interactionCount, 1);
  const calibration = await read(`users/${UID}/humor/calibration`);
  assert.equal(calibration.completedCount, 1, "double tap inflated calibration");
  const state = await read(`users/${UID}/humor/core`);
  assert.deepEqual(Object.keys(state.answers), [V(1)]);
  assert.deepEqual(state.today.contentIds, Vs(1, 15), "the day froze on the first response");
});

step("concurrent ratings of different cards do not lose an update", async () => {
  const targets = Vs(2, 6);
  const results = await Promise.allSettled(targets.map((id) => respond(UID, id, "funny")));
  const rejected = results.filter((r) => r.status === "rejected");
  assert.equal(
    rejected.length,
    0,
    `transactions failed instead of retrying: ${rejected.map((r) => r.reason).join("; ")}`,
  );
  const state = await read(`users/${UID}/humor/core`);
  assert.equal(Object.keys(state.answers).length, 6, "lost a Core progress update");
  assert.equal((await read(`users/${UID}/humor/summary`)).interactionCount, 6, "lost a profile update");
  const calibration = parseCalibrationState(await read(`users/${UID}/humor/calibration`));
  assert.equal(calibration.completedCount, 6);
  assert.equal(calibration.coveredSlots.length, 6, "V1–V6 cover the six baseline slots");
  assert.equal(calibration.degradedCount, 0);
});

step("interrupt after seven: a cold start resumes at V8", async () => {
  await respond(UID, V(7), "neutral");
  const feed = await core.getHumorCoreFeedView({db, uid: UID, nowMs: NOW + 60_000});
  assert.deepEqual(ids(feed.items), Vs(8, 15));
  assert.equal(feed.calibration.completedCount, 7);
  return `next ${feed.items[0].contentId}`;
});

step("the fifteenth rating completes the calibration, once", async () => {
  for (const [index, id] of Vs(8, 14).entries()) {
    await respond(UID, id, index % 3 === 0 ? "not_funny" : "funny");
  }
  assert.equal(parseCalibrationState(await read(`users/${UID}/humor/calibration`)).complete, false);
  const last = await respond(UID, V(15), "funny");
  assert.equal(last.onboardingCompletedNow, true);
  assert.equal(last.calibration.complete, true);

  const raw = await read(`users/${UID}/humor/calibration`);
  assert.equal(parseCalibrationState(raw).completedCount, CALIBRATION_TOTAL);
  assert.ok(raw.startedAt, "startedAt must be stamped");
  assert.ok(raw.completedAt, "completedAt must be stamped");
  const summary = await read(`users/${UID}/humor/summary`);
  assert.equal(summary.interactionCount, CALIBRATION_TOTAL);
  assert.equal(isHumorCalibrationReady(raw, summary), true);
  const state = await read(`users/${UID}/humor/core`);
  assert.equal(typeof state.initialCompletedAtMs, "number");
  const again = await respond(UID, V(15), "funny");
  assert.equal(again.alreadyAnswered, true);
});

step("the same day: the feed is closed and the daily five are locked", async () => {
  const feed = await core.getHumorCoreFeedView({db, uid: UID, nowMs: NOW});
  assert.deepEqual(feed.items, []);
  assert.equal(feed.catalogExhausted, true);
  assert.equal(feed.profileBuilding, false);
  const view = await daily.getDailyHumorSetView({db, uid: UID, nowMs: NOW});
  assert.deepEqual([view.status, view.lockedReason], ["locked", "starts_tomorrow"]);
  await assert.rejects(dailyAnswer(UID, TODAY, V(16), "funny"), (e) => e.reason === "slot-replaced");
  assert.equal((await read(`users/${UID}/humor/summary`)).interactionCount, CALIBRATION_TOTAL);
});

let day2;
step("the next logical day brings exactly V16–V20", async () => {
  day2 = await setDay(1);
  const view = await daily.getDailyHumorSetView({db, uid: UID, nowMs: NOW});
  assert.deepEqual([view.dayId, view.status, view.total], [day2, "ready", HUMOR_CORE.dailyCount]);
  assert.deepEqual(ids(view.items), Vs(16, 20));
  return ids(view.items).join(" ");
});

step("no run-ahead: rating V16 leaves V17–V20, and V21 is refused", async () => {
  const [a, b] = await Promise.all([
    dailyAnswer(UID, day2, V(16), "very_funny"),
    dailyAnswer(UID, day2, V(16), "very_funny"),
  ]);
  assert.deepEqual([a.answeredCount, b.answeredCount], [1, 1]);
  assert.equal((await read(`users/${UID}/humor/summary`)).interactionCount, CALIBRATION_TOTAL + 1);

  const view = await daily.getDailyHumorSetView({db, uid: UID, nowMs: NOW});
  assert.deepEqual(ids(view.items), Vs(16, 20));
  assert.equal(view.items[view.nextIndex].contentId, V(17));
  await assert.rejects(dailyAnswer(UID, day2, V(21), "funny"), (e) => e.reason === "slot-replaced");
  await assert.rejects(dailyAnswer(UID, TODAY, V(17), "funny"), (e) => e.reason === "day-closed");
  await assert.rejects(
    dailyAnswer(UID, day2, "ext_giphy_untrusted", "funny"),
    (e) => e.reason === "slot-replaced",
  );
  await assert.rejects(respond(UID, "ext_giphy_untrusted", "funny"), (e) => e.reason === "not-in-set");
  assert.equal((await db.doc(`users/${UID}/humorInteractions/ext_giphy_untrusted`).get()).exists, false);
});

step("a media failure is never evidence, and the day still completes", async () => {
  const before = await read(`users/${UID}/humor/summary`);
  const skip = await daily.submitDailyHumorResponse({
    db,
    uid: UID,
    nowMs: NOW,
    response: {dayId: day2, contentId: V(17), rating: null, skipped: true, dwellMs: 0, replayCount: 0},
  });
  assert.equal(skip.answeredCount, 2);
  const after = await read(`users/${UID}/humor/summary`);
  assert.equal(after.interactionCount, before.interactionCount);
  assert.deepEqual(after.vector, before.vector);

  let last;
  for (const id of Vs(18, 20)) last = await dailyAnswer(UID, day2, id, "funny");
  assert.deepEqual([last.total, last.answeredCount, last.completed], [5, 5, true]);
  const record = await read(`users/${UID}/humorDaily/${day2}`);
  assert.equal(record.schema, core.HUMOR_CORE_DAY_SCHEMA);
  assert.equal(record.completed, true);
  assert.ok(record.completedAt instanceof Timestamp);
  assert.equal(record.ratedCount, 4);
});

step("the day after: the failed entry leads, then V21–V24", async () => {
  const day3 = await setDay(2);
  const view = await daily.getDailyHumorSetView({db, uid: UID, nowMs: NOW});
  assert.deepEqual(ids(view.items), [V(17), ...Vs(21, 24)]);
  for (const id of ids(view.items)) await dailyAnswer(UID, day3, id, "funny");
});

step("missed days do not advance: three days later it is still V25–V29", async () => {
  const day7 = await setDay(6);
  const view = await daily.getDailyHumorSetView({db, uid: UID, nowMs: NOW});
  assert.equal(view.dayId, day7);
  assert.deepEqual(ids(view.items), Vs(25, 29));
  return ids(view.items).join(" ");
});

step("changing today's rating replaces it instead of stacking", async () => {
  const day7 = shiftDayId(TODAY, 6);
  await dailyAnswer(UID, day7, V(25), "very_funny");
  const liked = await read(`users/${UID}/humor/summary`);
  await dailyAnswer(UID, day7, V(25), "not_at_all");
  const changed = await read(`users/${UID}/humor/summary`);
  assert.equal(changed.interactionCount, liked.interactionCount);
  assert.equal((await read(`users/${UID}/humorInteractions/${V(25)}`)).rating, "not_at_all");
  assert.equal((await read(`users/${UID}/humor/core`)).answers[V(25)].rating, "not_at_all");
});

step("a member from before the sequence keeps everything and starts at V1, five a day", async () => {
  // Back to the real day: with no override the server clock decides.
  await db.doc(DAILY_DEV_CLOCK_DOC).delete();
  const uid = "qa_core_legacy";
  await db.doc(`users/${uid}/humor/calibration`).set({
    version: 1,
    completedCount: 15,
    complete: true,
    completedAt: Timestamp.fromMillis(NOW - 9 * DAY),
  });
  await db.doc(`users/${uid}/humor/summary`).set({
    vector: {sarcasm: 65, wordplay: 60},
    confidence: 0.4,
    interactionCount: 40,
    exploredCategories: [],
    version: 1,
  });
  await db.doc(`users/${uid}/humorInteractions/${V(3)}`).set({
    contentId: V(3),
    rating: "funny",
    skipped: false,
  });
  const views = await Promise.all(
    Array.from({length: 6}, () => daily.getDailyHumorSetView({db, uid, nowMs: NOW})),
  );
  for (const view of views) {
    assert.deepEqual(ids(view.items), [V(1), V(2), V(4), V(5), V(6)]);
  }
  const summary = await read(`users/${uid}/humor/summary`);
  assert.equal(summary.interactionCount, 40);
  assert.deepEqual(summary.vector, {sarcasm: 65, wordplay: 60});
  const state = await read(`users/${uid}/humor/core`);
  assert.equal(state.migration.from, "adaptive-v1");
  assert.equal(state.migration.importedRatings, 1);

  await dailyAnswer(uid, TODAY, V(1), "very_funny");
  assert.equal((await read(`users/${uid}/humor/summary`)).interactionCount, 41);
  assert.equal(parseCalibrationState(await read(`users/${uid}/humor/calibration`)).complete, true);
});

step("concurrent ratings keep content stats exact", async () => {
  const contentId = V(30);
  const before = (await read(`humorContent/${contentId}`)).stats ?? {};
  const users = ["qa_stats_1", "qa_stats_2", "qa_stats_3", "qa_stats_4"];
  const ratings = ["very_funny", "funny", "not_funny", "not_at_all"];
  const results = await Promise.allSettled(
    users.map((uid, i) => submitHumorFeedbackTx({db, uid, contentId, rating: ratings[i]})),
  );
  assert.equal(results.filter((r) => r.status === "rejected").length, 0);
  const stats = (await read(`humorContent/${contentId}`)).stats;
  assert.equal(stats.ratingCount, Number(before.ratingCount ?? 0) + users.length);
  assert.ok(Math.abs(stats.ratingSum - (Number(before.ratingSum ?? 0) + 1 + 0.6 - 0.5 - 1)) < 1e-9);
});

step("account deletion removes Core progress through the existing humor sweep", async () => {
  const uid = "qa_core_deletion";
  for (const id of Vs(1, 3)) await respond(uid, id, "funny");
  assert.ok((await db.doc(`users/${uid}/humor/core`).get()).exists);
  // Exactly what deleteAccount.ts runs for humor-owned data.
  for (const path of [
    `users/${uid}/humor`,
    `users/${uid}/humorInteractions`,
    `users/${uid}/humorDaily`,
  ]) {
    const snap = await db.collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  assert.equal((await db.doc(`users/${uid}/humor/core`).get()).exists, false);
  assert.equal((await db.doc(`users/${uid}/humor/calibration`).get()).exists, false);
  assert.equal((await db.collection(`users/${uid}/humorInteractions`).get()).empty, true);
  for (const root of ["humorCore", "humorCoreProgress", "humorDailySets"]) {
    assert.equal((await db.collection(root).get()).empty, true, `orphaned collection: ${root}`);
  }
});

(async () => {
  let failed = 0;
  await db.doc(DAILY_DEV_CLOCK_DOC).delete();
  for (const [name, fn] of steps) {
    try {
      const detail = await fn();
      console.log(`PASS  ${name}${detail ? ` — ${detail}` : ""}`);
    } catch (error) {
      failed += 1;
      console.error(`FAIL  ${name}\n      ${error && error.stack ? error.stack : error}`);
    }
  }
  await db.doc(DAILY_DEV_CLOCK_DOC).delete();
  console.log(`\n${steps.length - failed}/${steps.length} humor core steps passed`);
  process.exit(failed === 0 ? 0 : 1);
})();
