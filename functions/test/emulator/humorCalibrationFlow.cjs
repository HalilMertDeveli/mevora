/**
 * Runtime calibration smoke test against the real Firestore emulator.
 *
 * The unit suite (`functions/test/humorCalibration.test.cjs`) proves the policy
 * with an in-memory double. This exercises the same flow through actual
 * Firestore semantics — real queries, real transactions, real merge writes —
 * which is where an index or a nested-map merge would break instead.
 *
 * Deliberately lives in a subdirectory so `testSuiteCoverage.test.cjs` does not
 * demand it in the emulator-free `npm test` list.
 *
 * Run from the repo root:
 *   npx firebase emulators:exec --only firestore --project mevora-calibration-qa \
 *     "node functions/test/emulator/humorCalibrationFlow.cjs"
 */
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST is not set — refusing to run.");
  process.exit(2);
}

const {
  CALIBRATION_TOTAL,
  ANCHOR_INTERACTIONS,
  ADAPTIVE_INTERACTIONS,
  EXPLORATION_INTERACTIONS,
  HUMOR_CALIBRATION_VERSION,
  parseCalibrationState,
} = require("../../lib/humor/calibration.js");
const {
  INTERNAL_HUMOR_SEED,
  upsertHumorContentDoc,
  listCalibrationPool,
} = require("../../lib/humor/contentRepository.js");
const {buildHumorFeed, loadUserHumorCalibration} = require("../../lib/humor/feed.js");
const {submitHumorFeedbackTx} = require("../../lib/humor/feedback.js");

initializeApp({projectId: process.env.GCLOUD_PROJECT || "mevora-calibration-qa"});
const db = getFirestore();

const UID = "qa_calibration_user";
const steps = [];

function step(name, fn) {
  steps.push([name, fn]);
}

step("seed the curated catalog", async () => {
  for (const item of INTERNAL_HUMOR_SEED) {
    await upsertHumorContentDoc(db, {...item, safetyStatus: "approved", active: true});
  }
  // Provider-shaped content: approved and servable, but never curated. It must
  // not appear in the pool, and its slot claim must be ignored.
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
  assert.ok(pool.length >= CALIBRATION_TOTAL, `pool too small: ${pool.length}`);
  const ids = pool.map((item) => item.contentId);
  assert.equal(
    ids.includes("ext_giphy_untrusted"),
    false,
    "uncurated provider content reached the calibration pool",
  );
  const all = await db.collection("humorContent").get();
  assert.ok(pool.length < all.docs.length, "the query must actually filter");
  return `${pool.length} curated of ${all.docs.length} total; provider item excluded`;
});

step("start calibration: first page is anchor-led and exactly 15", async () => {
  const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 15});
  assert.equal(feed.calibration.stage, "anchor");
  assert.equal(feed.calibration.completedCount, 0);
  assert.equal(feed.calibration.complete, false);
  assert.equal(feed.calibration.insufficientPool, false);
  assert.equal(feed.items.length, CALIBRATION_TOTAL);

  const stages = feed.items.map((i) => i.calibrationStage);
  assert.equal(stages.filter((s) => s === "anchor").length, ANCHOR_INTERACTIONS);
  assert.equal(stages.filter((s) => s === "adaptive").length, ADAPTIVE_INTERACTIONS);
  assert.equal(
    stages.filter((s) => s === "exploration").length,
    EXPLORATION_INTERACTIONS,
  );
  const ids = feed.items.map((i) => i.contentId);
  assert.equal(new Set(ids).size, ids.length, "duplicate content in calibration page");
  // Feed cards must not leak curation internals.
  for (const item of feed.items) {
    assert.equal("calibrationSlot" in item, false);
    assert.equal("humorVector" in item, false);
    assert.equal("safetyFlags" in item, false);
  }
  return `stages ${stages.join(",")}`;
});

step("rate through the anchor stage", async () => {
  const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 15});
  for (const item of feed.items.slice(0, ANCHOR_INTERACTIONS)) {
    await submitHumorFeedbackTx({
      db,
      uid: UID,
      contentId: item.contentId,
      rating: "very_funny",
    });
  }
  const state = await loadUserHumorCalibration(db, UID);
  assert.equal(state.completedCount, ANCHOR_INTERACTIONS);
  assert.equal(state.stage, "adaptive");
  assert.equal(state.coveredSlots.length, ANCHOR_INTERACTIONS, "all six slots covered");
  assert.equal(state.degradedCount, 0, "every anchor came from the curated pool");
  return `slots ${state.coveredSlots.join(",")}`;
});

step("interrupt and resume: next page continues at adaptive", async () => {
  // A fresh buildHumorFeed call is exactly what a cold app start does.
  const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 15});
  assert.equal(feed.calibration.stage, "adaptive");
  assert.equal(feed.calibration.completedCount, ANCHOR_INTERACTIONS);
  assert.equal(feed.items.length, CALIBRATION_TOTAL - ANCHOR_INTERACTIONS);
  assert.equal(feed.items[0].calibrationStage, "adaptive");

  const state = await loadUserHumorCalibration(db, UID);
  const rated = new Set(state.ratedContentIds);
  for (const item of feed.items) {
    assert.equal(rated.has(item.contentId), false, `re-served ${item.contentId}`);
  }
  return `${feed.items.length} items remaining`;
});

step("complete item 15", async () => {
  let guard = 0;
  while (guard < 40) {
    const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 15});
    if (feed.calibration.complete || feed.items.length === 0) {
      break;
    }
    await submitHumorFeedbackTx({
      db,
      uid: UID,
      contentId: feed.items[0].contentId,
      rating: guard % 3 === 0 ? "not_funny" : "funny",
    });
    guard += 1;
  }
  const state = await loadUserHumorCalibration(db, UID);
  assert.equal(state.completedCount, CALIBRATION_TOTAL);
  assert.equal(state.complete, true);
  assert.equal(state.stage, "complete");
  assert.equal(new Set(state.ratedContentIds).size, CALIBRATION_TOTAL);

  const raw = (await db.doc(`users/${UID}/humor/calibration`).get()).data();
  assert.ok(raw.completedAt, "completedAt must be stamped");
  assert.ok(raw.startedAt, "startedAt must be stamped");
  assert.equal(parseCalibrationState(raw).complete, true);
  return `completed with degradedCount=${state.degradedCount}`;
});

step("post-calibration: the feed leaves calibration mode", async () => {
  const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 12});
  assert.equal(feed.calibration.complete, true);
  assert.equal(feed.profileBuilding, false);
  for (const item of feed.items) {
    assert.equal(
      item.calibrationStage,
      null,
      "ordinary feed content must not be labelled a calibration item",
    );
  }
  return `${feed.items.length} ordinary items`;
});

step("interaction 16 keeps the lifetime profile learning", async () => {
  const before = (await db.doc(`users/${UID}/humor/summary`).get()).data();
  assert.equal(before.interactionCount, CALIBRATION_TOTAL);

  const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 12});
  assert.ok(feed.items.length > 0, "no unrated content left to prove learning with");
  const result = await submitHumorFeedbackTx({
    db,
    uid: UID,
    contentId: feed.items[0].contentId,
    rating: "very_funny",
  });

  const after = (await db.doc(`users/${UID}/humor/summary`).get()).data();
  assert.equal(after.interactionCount, CALIBRATION_TOTAL + 1);
  assert.ok(
    after.confidence > before.confidence,
    `confidence must keep growing (${before.confidence} → ${after.confidence})`,
  );
  assert.notDeepEqual(after.vector, before.vector, "the humor vector must still move");
  assert.equal(result.calibration.completedCount, CALIBRATION_TOTAL);
  assert.equal(result.calibration.complete, true);
  assert.equal(result.profileBuilding, false);

  const state = await loadUserHumorCalibration(db, UID);
  assert.equal(state.completedCount, CALIBRATION_TOTAL, "milestone stays frozen at 15");
  return `interactionCount ${before.interactionCount} → ${after.interactionCount}`;
});

step("a second user gets the same slots but rotated content", async () => {
  const other = "qa_calibration_user_two";
  const mine = await db.doc(`users/${UID}/humor/calibration`).get();
  const feed = await buildHumorFeed({db, uid: other, languages: ["tr", "en"], limit: 15});
  const anchors = feed.items
    .filter((i) => i.calibrationStage === "anchor")
    .map((i) => i.contentId);
  assert.equal(anchors.length, ANCHOR_INTERACTIONS);
  const myFirstSix = mine.data().ratedContentIds.slice(0, ANCHOR_INTERACTIONS);
  const overlap = anchors.filter((id) => myFirstSix.includes(id));
  assert.ok(
    overlap.length < ANCHOR_INTERACTIONS,
    "two users must not receive an identical anchor set",
  );
  return `${ANCHOR_INTERACTIONS - overlap.length}/${ANCHOR_INTERACTIONS} anchors differ`;
});

step("rapid double tap on one card counts exactly once", async () => {
  const uid = "qa_concurrency_same";
  const feed = await buildHumorFeed({db, uid, languages: ["tr", "en"], limit: 15});
  const target = feed.items[0].contentId;

  // Two in-flight submissions for the same card — the real double-tap shape.
  const results = await Promise.allSettled([
    submitHumorFeedbackTx({db, uid, contentId: target, rating: "very_funny"}),
    submitHumorFeedbackTx({db, uid, contentId: target, rating: "very_funny"}),
  ]);
  const ok = results.filter((r) => r.status === "fulfilled").length;
  assert.ok(ok >= 1, `both submissions failed: ${JSON.stringify(results)}`);

  const state = await loadUserHumorCalibration(db, uid);
  assert.equal(state.completedCount, 1, "double tap inflated calibration");
  assert.deepEqual(state.ratedContentIds, [target]);
  const summary = (await db.doc(`users/${uid}/humor/summary`).get()).data();
  assert.equal(summary.interactionCount, 1, "double tap inflated interactionCount");
  return `${ok}/2 submissions succeeded, count stayed 1`;
});

step("concurrent ratings of different cards do not lose an update", async () => {
  const uid = "qa_concurrency_distinct";
  const feed = await buildHumorFeed({db, uid, languages: ["tr", "en"], limit: 15});
  const targets = feed.items.slice(0, 5).map((i) => i.contentId);

  const results = await Promise.allSettled(
    targets.map((contentId) =>
      submitHumorFeedbackTx({db, uid, contentId, rating: "funny"}),
    ),
  );
  const rejected = results.filter((r) => r.status === "rejected");
  assert.equal(
    rejected.length,
    0,
    `transactions failed instead of retrying: ${rejected.map((r) => r.reason).join("; ")}`,
  );

  const state = await loadUserHumorCalibration(db, uid);
  assert.equal(state.completedCount, targets.length, "lost calibration update");
  assert.equal(new Set(state.ratedContentIds).size, targets.length);
  const summary = (await db.doc(`users/${uid}/humor/summary`).get()).data();
  assert.equal(summary.interactionCount, targets.length, "lost profile update");
  return `${targets.length} concurrent ratings all landed`;
});

step("re-rating after completion cannot restart or extend calibration", async () => {
  const state = await loadUserHumorCalibration(db, UID);
  assert.equal(state.complete, true, "precondition: UID finished calibration");
  const before = (await db.doc(`users/${UID}/humor/summary`).get()).data();

  // Re-rate an item that was part of calibration, twice, concurrently.
  const replay = state.ratedContentIds[0];
  await Promise.allSettled([
    submitHumorFeedbackTx({db, uid: UID, contentId: replay, rating: "not_at_all"}),
    submitHumorFeedbackTx({db, uid: UID, contentId: replay, rating: "funny"}),
  ]);

  const after = await loadUserHumorCalibration(db, UID);
  assert.equal(after.completedCount, CALIBRATION_TOTAL);
  assert.equal(after.complete, true);
  assert.equal(after.ratedContentIds.length, CALIBRATION_TOTAL);
  const summary = (await db.doc(`users/${UID}/humor/summary`).get()).data();
  assert.equal(
    summary.interactionCount,
    before.interactionCount,
    "re-rating known content must not increment the lifetime counter",
  );
  return `stayed at ${after.completedCount}/${CALIBRATION_TOTAL}`;
});

step("account deletion removes calibration through the existing humor sweep", async () => {
  const uid = "qa_deletion_user";
  const feed = await buildHumorFeed({db, uid, languages: ["tr", "en"], limit: 15});
  for (const item of feed.items.slice(0, 3)) {
    await submitHumorFeedbackTx({db, uid, contentId: item.contentId, rating: "funny"});
  }
  assert.ok((await db.doc(`users/${uid}/humor/calibration`).get()).exists);
  assert.ok((await db.doc(`users/${uid}/humor/summary`).get()).exists);
  const interactions = await db.collection(`users/${uid}/humorInteractions`).get();
  assert.equal(interactions.docs.length, 3);

  // Exactly what deleteAccount.ts runs for humor-owned data.
  for (const path of [`users/${uid}/humor`, `users/${uid}/humorInteractions`]) {
    const snap = await db.collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }

  assert.equal((await db.doc(`users/${uid}/humor/calibration`).get()).exists, false);
  assert.equal((await db.doc(`users/${uid}/humor/summary`).get()).exists, false);
  assert.equal((await db.collection(`users/${uid}/humorInteractions`).get()).empty, true);

  // No calibration-specific document may live outside that swept collection.
  const orphanRoots = ["humorCalibration", "humorCalibrations", "calibration"];
  for (const root of orphanRoots) {
    assert.equal(
      (await db.collection(root).get()).empty,
      true,
      `orphaned calibration collection: ${root}`,
    );
  }
  return "summary + calibration + interactions all gone, no orphans";
});

(async () => {
  let failed = 0;
  for (const [name, fn] of steps) {
    try {
      const detail = await fn();
      console.log(`PASS  ${name}${detail ? ` — ${detail}` : ""}`);
    } catch (error) {
      failed += 1;
      console.error(`FAIL  ${name}\n      ${error.message}`);
    }
  }
  console.log(`\n${steps.length - failed}/${steps.length} emulator steps passed`);
  process.exit(failed === 0 ? 0 : 1);
})();
