/**
 * Feed pagination against the real Firestore emulator.
 *
 * The in-memory suite proves the algorithm. This proves the parts only a real
 * Firestore can: the composite index, `orderBy` + `startAfter` cursor
 * semantics, and that a document missing `createdAt` really does drop out of
 * an ordered query.
 *
 * Run from the repo root:
 *   npx firebase emulators:exec --only firestore --project mevora-feed-qa \
 *     "node functions/test/emulator/humorFeedPaginationFlow.cjs"
 */
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST is not set — refusing to run.");
  process.exit(2);
}

const {CALIBRATION_TOTAL} = require("../../lib/humor/calibration.js");
const {listHumorContentPage} = require("../../lib/humor/contentRepository.js");
const {buildHumorFeed} = require("../../lib/humor/feed.js");
const {submitHumorFeedbackTx} = require("../../lib/humor/feedback.js");

initializeApp({projectId: process.env.GCLOUD_PROJECT || "mevora-feed-qa"});
const db = getFirestore();

const CATALOG_SIZE = 400;
const UID = "qa_feed_user";
const steps = [];
const step = (name, fn) => steps.push([name, fn]);

/** Skip calibration: this script is about the generic post-calibration feed. */
async function completeCalibration(uid) {
  await db.doc(`users/${uid}/humor/calibration`).set({
    version: 1,
    completedCount: CALIBRATION_TOTAL,
    stage: "complete",
    complete: true,
    ratedContentIds: [],
    coveredSlots: [],
    coveredDimensions: [],
    degradedCount: 0,
  });
}

step("seed a catalog far larger than the old 120 window", async () => {
  const base = Date.now() - CATALOG_SIZE * 1000;
  let batch = db.batch();
  for (let i = 0; i < CATALOG_SIZE; i += 1) {
    const id = `hc_${String(i).padStart(4, "0")}`;
    batch.set(db.doc(`humorContent/${id}`), {
      contentId: id,
      type: "meme",
      language: i % 5 === 0 ? "en" : "tr",
      category: "meme",
      humorTags: [],
      humorVector: {meme: 0.6 + (i % 4) * 0.1},
      media: {downloadUrl: `https://example.test/${id}.png`},
      safetyStatus: "approved",
      safetyFlags: {},
      source: {type: "internal", provider: "mevora-internal", licenseRef: null},
      active: true,
      createdAt: Timestamp.fromMillis(base + i * 1000),
      stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    });
    if (i % 400 === 399) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
  await completeCalibration(UID);
  const all = await db.collection("humorContent").get();
  assert.equal(all.docs.length, CATALOG_SIZE);
  return `${CATALOG_SIZE} documents`;
});

step("ordered pagination walks the whole catalog without repeats", async () => {
  const seen = new Set();
  let after = null;
  let pages = 0;
  while (pages < 50) {
    const page = await listHumorContentPage(db, {
      languages: ["tr", "en"],
      pageSize: 60,
      after,
    });
    for (const entry of page.entries) {
      assert.equal(seen.has(entry.content.contentId), false, "duplicate in scan");
      seen.add(entry.content.contentId);
    }
    pages += 1;
    if (page.exhausted) break;
    after = page.scannedTo;
  }
  assert.equal(seen.size, CATALOG_SIZE, `scan reached ${seen.size}/${CATALOG_SIZE}`);
  return `${seen.size} documents in ${pages} query pages`;
});

step("the feed serves far past 120 items and never repeats", async () => {
  const served = [];
  let cursor = null;
  let calls = 0;
  while (calls < 60) {
    const result = await buildHumorFeed({
      db,
      uid: UID,
      languages: ["tr", "en"],
      limit: 12,
      cursor,
    });
    if (result.items.length === 0) {
      assert.equal(result.nextCursor, null, "empty page still invited another");
      break;
    }
    served.push(...result.items.map((i) => i.contentId));
    cursor = result.nextCursor;
    calls += 1;
    if (!cursor) break;
  }
  assert.equal(new Set(served).size, served.length, "the feed repeated content");
  assert.ok(
    served.length > 120,
    `stalled at ${served.length} — the 120-document window is back`,
  );
  assert.ok(
    served.length >= CATALOG_SIZE - 12,
    `only reached ${served.length}/${CATALOG_SIZE}`,
  );
  return `${served.length} items across ${calls} calls`;
});

step("rated content is never served again", async () => {
  const uid = "qa_feed_rater";
  await completeCalibration(uid);

  const first = await buildHumorFeed({
    db,
    uid,
    languages: ["tr", "en"],
    limit: 12,
  });
  assert.equal(first.items.length, 12);
  for (const item of first.items) {
    await submitHumorFeedbackTx({
      db,
      uid,
      contentId: item.contentId,
      rating: "funny",
    });
  }
  const ratedIds = new Set(first.items.map((i) => i.contentId));

  // A fresh call with no cursor restarts at the top of the catalog: the rated
  // items must be skipped rather than served again.
  const second = await buildHumorFeed({
    db,
    uid,
    languages: ["tr", "en"],
    limit: 12,
  });
  for (const item of second.items) {
    assert.equal(ratedIds.has(item.contentId), false, `re-served ${item.contentId}`);
  }
  assert.equal(second.items.length, 12);
  return "12 rated, 12 fresh";
});

step("a single-language feed stays in that language", async () => {
  const uid = "qa_feed_tr";
  await completeCalibration(uid);
  const result = await buildHumorFeed({db, uid, languages: ["tr"], limit: 12});
  assert.equal(result.items.length, 12);
  for (const item of result.items) {
    assert.equal(item.language, "tr");
  }
  return "12/12 Turkish";
});

step("inactive and unapproved content never surfaces", async () => {
  const uid = "qa_feed_safety";
  await completeCalibration(uid);
  await db.doc("humorContent/hc_0399").set({active: false}, {merge: true});
  await db.doc("humorContent/hc_0398").set({safetyStatus: "rejected"}, {merge: true});
  await db.doc("humorContent/hc_0397").set({safetyStatus: "needs_review"}, {merge: true});

  const blocked = new Set(["hc_0399", "hc_0398", "hc_0397"]);
  let cursor = null;
  let calls = 0;
  const served = [];
  while (calls < 60) {
    const result = await buildHumorFeed({
      db,
      uid,
      languages: ["tr", "en"],
      limit: 12,
      cursor,
    });
    served.push(...result.items.map((i) => i.contentId));
    cursor = result.nextCursor;
    calls += 1;
    if (!cursor || result.items.length === 0) break;
  }
  for (const id of blocked) {
    assert.equal(served.includes(id), false, `served blocked ${id}`);
  }
  return `${served.length} served, 3 blocked items excluded`;
});

step("a document without createdAt is invisible to the ordered feed", async () => {
  // Locks the invariant the pagination key depends on. `upsertHumorContentDoc`
  // always stamps createdAt; this proves why that matters.
  await db.doc("humorContent/hc_no_created").set({
    contentId: "hc_no_created",
    type: "meme",
    language: "tr",
    category: "meme",
    humorTags: [],
    humorVector: {meme: 0.9},
    media: {downloadUrl: "https://example.test/x.png"},
    safetyStatus: "approved",
    safetyFlags: {},
    source: {type: "internal", provider: "mevora-internal", licenseRef: null},
    active: true,
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
  });
  const page = await listHumorContentPage(db, {
    languages: ["tr"],
    pageSize: 100,
  });
  assert.equal(
    page.entries.some((e) => e.content.contentId === "hc_no_created"),
    false,
    "Firestore ordered queries are expected to exclude it",
  );
  await db.doc("humorContent/hc_no_created").delete();
  return "confirmed";
});

step("an exhausted catalog reports exhaustion and stops paginating", async () => {
  const uid = "qa_feed_small";
  await completeCalibration(uid);
  // Rate everything this user can be served. The client always calls with a
  // null cursor, as a cold start would: the server-persisted feed position is
  // what must keep the walk moving.
  let guard = 0;
  let rated = 0;
  while (guard < 120) {
    const result = await buildHumorFeed({
      db,
      uid,
      languages: ["tr", "en"],
      limit: 15,
      cursor: null,
    });
    for (const item of result.items) {
      await submitHumorFeedbackTx({db, uid, contentId: item.contentId, rating: "neutral"});
      rated += 1;
    }
    // An empty page with a cursor still attached means "nothing servable in
    // that stretch, keep going" — only a null cursor ends the walk.
    if (result.items.length === 0 && result.nextCursor === null) {
      assert.equal(result.catalogExhausted, true, "should report exhaustion");
      assert.equal(result.catalogEmpty, false, "the catalog is not empty");
      assert.ok(rated > 300, `only rated ${rated} before exhaustion`);
      return `exhausted after ${guard} pages, ${rated} rated`;
    }
    guard += 1;
  }
  throw new Error(`never reached exhaustion (rated ${rated})`);
});

step("an empty catalog is distinguishable from an exhausted one", async () => {
  const empty = getFirestore();
  const uid = "qa_feed_emptycat";
  // Use a collection-free project path by filtering to a language with no
  // content rather than wiping the shared catalog.
  await completeCalibration(uid);
  const result = await buildHumorFeed({db, uid, languages: ["zz"], limit: 12});
  assert.deepEqual(result.items, []);
  assert.equal(result.nextCursor, null);
  assert.equal(result.catalogEmpty, true, "no servable content for this language");
  assert.ok(empty);
  return "empty state reported";
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
