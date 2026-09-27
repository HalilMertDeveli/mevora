/**
 * Feed pagination against the real Firestore emulator.
 *
 * The in-memory suite proves the algorithm. This proves the parts only a real
 * Firestore can: `orderBy` + `startAfter`/`endBefore` cursor semantics at full
 * timestamp precision, real commit timestamps shared by a whole batch, what a
 * forged cursor does to a real query, and that a document missing `createdAt`
 * really does drop out of an ordered query.
 *
 * Run both humor emulator flows (starts a throwaway Firestore emulator; see
 * runHumorEmulatorFlows.cjs for choosing ports):
 *   npm --prefix functions run test:emulator:humor
 *
 * Or this flow alone inside an emulator you started yourself:
 *   npx firebase emulators:exec --only firestore --project demo-humor-feed-qa \
 *     "node functions/test/emulator/humorFeedPaginationFlow.cjs"
 */
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore, Timestamp} = require("firebase-admin/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST is not set — refusing to run.");
  process.exit(2);
}

const {
  ANCHOR_SLOTS,
  CALIBRATION_TOTAL,
  HUMOR_CALIBRATION_VERSION,
} = require("../../lib/humor/calibration.js");
const {listHumorContentPage} = require("../../lib/humor/contentRepository.js");
const {buildHumorFeed} = require("../../lib/humor/feed.js");
const {submitHumorFeedbackTx} = require("../../lib/humor/feedback.js");

initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-humor-feed-qa"});
const db = getFirestore();

const CATALOG_SIZE = 400;
const UID = "qa_feed_user";
const LANGS = ["tr", "en"];
const steps = [];
const step = (name, fn) => steps.push([name, fn]);

const cursorFor = (body) => Buffer.from(JSON.stringify(body), "utf8").toString("base64url");

/** Write interaction docs in batches (rating, skip marker or report marker). */
async function markInteractions(uid, contentIds, marker = {rating: "funny"}) {
  let batch = db.batch();
  let pending = 0;
  for (const contentId of contentIds) {
    batch.set(db.doc(`users/${uid}/humorInteractions/${contentId}`), {contentId, ...marker});
    pending += 1;
    if (pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  await batch.commit();
}

async function servableIds(languages) {
  const snap = await db
    .collection("humorContent")
    .where("active", "==", true)
    .where("safetyStatus", "==", "approved")
    .get();
  return snap.docs
    .filter((doc) => doc.get("createdAt") && languages.includes(doc.get("language")))
    .map((doc) => doc.id);
}

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

step("the feed walks the whole catalog: exactly 400 of 400, no repeats", async () => {
  const served = [];
  let cursor = null;
  let calls = 0;
  while (calls < 60) {
    const result = await buildHumorFeed({
      db,
      uid: UID,
      languages: LANGS,
      limit: 12,
      cursor,
    });
    served.push(...result.items.map((i) => i.contentId));
    cursor = result.nextCursor;
    calls += 1;
    if (!cursor) break;
  }
  assert.equal(new Set(served).size, served.length, "the feed repeated content");
  assert.equal(served.length, CATALOG_SIZE, `reached ${served.length}/${CATALOG_SIZE}`);
  return `${served.length} items across ${calls} calls`;
});

step("a cold start re-offers fetched-but-unrated items from the stored position", async () => {
  const uid = "qa_feed_resume";
  await completeCalibration(uid);
  const pageA = await buildHumorFeed({db, uid, languages: LANGS, limit: 12});
  const pageB = await buildHumorFeed({
    db,
    uid,
    languages: LANGS,
    limit: 12,
    cursor: pageA.nextCursor,
  });
  const idsA = pageA.items.map((i) => i.contentId);
  const idsB = pageB.items.map((i) => i.contentId);
  for (const contentId of [...idsA, ...idsB.slice(0, 4)]) {
    await submitHumorFeedbackTx({db, uid, contentId, rating: "funny"});
  }

  // No cursor: only the server-held position can bring page B back.
  const resumed = await buildHumorFeed({db, uid, languages: LANGS, limit: 12});
  const resumedIds = resumed.items.map((i) => i.contentId);
  for (const id of idsB.slice(4)) {
    assert.ok(resumedIds.includes(id), `fetched-but-unrated ${id} was skipped`);
  }
  for (const id of [...idsA, ...idsB.slice(0, 4)]) {
    assert.equal(resumedIds.includes(id), false, `re-served rated ${id}`);
  }
  const stored = (await db.doc(`users/${uid}/humor/summary`).get()).data();
  assert.equal(stored.feedPosition.v, 2, "walk state must be the full-precision format");
  assert.ok(stored.vector, "writing the walk state must not clobber the profile");
  return `${idsB.length - 4} carried over, ${resumed.items.length} served`;
});

step("a legacy millisecond position still resumes", async () => {
  const uid = "qa_feed_legacy";
  await completeCalibration(uid);
  const boundary = await db.doc("humorContent/hc_0200").get();
  await db.doc(`users/${uid}/humor/summary`).set({
    feedPosition: {createdAtMs: boundary.get("createdAt").toMillis(), contentId: "hc_0200"},
  });
  const result = await buildHumorFeed({db, uid, languages: LANGS, limit: 12});
  const indexes = result.items.map((i) => Number(i.contentId.slice(3)));
  assert.equal(result.items.length, 12);
  assert.ok(Math.max(...indexes) <= 200, "a legacy position jumped back up the catalog");
  assert.ok(indexes.includes(199), "the item after a legacy position was skipped");
  return `resumed at ${Math.max(...indexes)}`;
});

step("forged cursors fall back instead of failing the query", async () => {
  const uid = "qa_feed_forged";
  await completeCalibration(uid);
  const forged = [
    cursorFor({createdAtMs: 1e20, contentId: "hc_0010"}),
    cursorFor({s: 1e15, n: 0, id: "hc_0010"}),
    cursorFor({createdAtMs: Date.now(), contentId: "a/b"}),
    cursorFor({s: 1_700_000_000, n: 0, id: "x".repeat(200)}),
    cursorFor({s: 1_700_000_000, n: 0, id: "hc_0010", pad: "p".repeat(600)}),
  ];
  for (const cursor of forged) {
    const result = await buildHumorFeed({db, uid, languages: LANGS, limit: 12, cursor});
    assert.equal(result.items.length, 12, `cursor ${cursor.slice(0, 24)}… broke the feed`);
  }
  return `${forged.length} forged cursors degraded cleanly`;
});

step("skip and report markers keep content out", async () => {
  const uid = "qa_feed_markers";
  await completeCalibration(uid);
  const skipped = ["hc_0399", "hc_0398", "hc_0396"];
  const reported = ["hc_0395"];
  await markInteractions(uid, skipped, {skipped: true, rating: null});
  await markInteractions(uid, reported, {reported: true, skipped: true});
  const result = await buildHumorFeed({db, uid, languages: LANGS, limit: 12});
  for (const id of [...skipped, ...reported]) {
    assert.equal(
      result.items.some((i) => i.contentId === id),
      false,
      `served marked ${id}`,
    );
  }
  assert.equal(result.items.length, 12);
  return "4 marked items excluded";
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
      const servable = await servableIds(LANGS);
      assert.equal(rated, servable.length, `rated ${rated} of ${servable.length} servable`);
      // The catalog is larger than one call's scan budget: the old code reset
      // to the top here and alternated "empty, try again" / "caught up".
      for (const label of ["first", "second"]) {
        const again = await buildHumorFeed({db, uid, languages: LANGS, limit: 15});
        assert.equal(again.catalogExhausted, true, `${label} cold call after exhaustion`);
        assert.deepEqual(again.items, []);
        assert.equal(again.nextCursor, null);
      }
      return `exhausted after ${guard} pages, ${rated} rated, stable on 2 more cold calls`;
    }
    guard += 1;
  }
  throw new Error(`never reached exhaustion (rated ${rated})`);
});

step("a pre-rated catalog larger than the scan budget: no false or flapping exhaustion", async () => {
  const uid = "qa_feed_prerated";
  await completeCalibration(uid);
  const servable = await servableIds(LANGS);
  assert.ok(servable.length > 240, `catalog of ${servable.length} fits one call`);
  await markInteractions(uid, servable);

  const first = await buildHumorFeed({db, uid, languages: LANGS, limit: 12});
  assert.deepEqual(first.items, []);
  assert.equal(first.catalogExhausted, false, "claimed exhaustion from a partial walk");
  assert.ok(first.nextCursor, "a partial walk must invite the next page");

  const results = [];
  for (let i = 0; i < 3; i += 1) {
    results.push(await buildHumorFeed({db, uid, languages: LANGS, limit: 12}));
  }
  for (const [index, result] of results.entries()) {
    assert.equal(result.catalogExhausted, true, `cold call ${index + 2} not exhausted`);
    assert.deepEqual(result.items, []);
  }
  return `${servable.length} rated; partial first call, then exhausted ×3`;
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
  assert.equal(result.catalogExhausted, false, "empty is not caught up");
  assert.ok(empty);
  return "empty state reported";
});

step("a batch sharing one commit timestamp is walked without skips", async () => {
  // A single batch commit stamps every document with the same server
  // timestamp, so page boundaries fall inside one timestamp group and only the
  // id tie-break keeps the walk moving. Production stamps at microsecond
  // precision, where millisecond positions skipped the rest of such a group;
  // the emulator stamps whole milliseconds, so the sub-millisecond case itself
  // is pinned by the unit suite.
  const uid = "qa_feed_precision";
  await completeCalibration(uid);
  const batch = db.batch();
  const ids = [];
  for (let i = 0; i < 30; i += 1) {
    const id = `hp_${String(i).padStart(2, "0")}`;
    ids.push(id);
    batch.set(db.doc(`humorContent/${id}`), {
      contentId: id,
      type: "meme",
      language: "pt",
      category: "meme",
      humorTags: [],
      humorVector: {meme: 0.7},
      media: {downloadUrl: `https://example.test/${id}.png`},
      safetyStatus: "approved",
      safetyFlags: {},
      source: {type: "internal", provider: "mevora-internal", licenseRef: null},
      active: true,
      createdAt: FieldValue.serverTimestamp(),
      stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    });
  }
  await batch.commit();
  const stamps = new Set(
    (await db.getAll(...ids.map((id) => db.doc(`humorContent/${id}`)))).map((snap) => {
      const createdAt = snap.get("createdAt");
      return `${createdAt.seconds}.${createdAt.nanoseconds}`;
    }),
  );
  assert.equal(stamps.size, 1, "the batch should share one commit timestamp");

  const served = [];
  let cursor = null;
  for (let calls = 0; calls < 10; calls += 1) {
    const result = await buildHumorFeed({db, uid, languages: ["pt"], limit: 10, cursor});
    served.push(...result.items.map((i) => i.contentId));
    cursor = result.nextCursor;
    if (!cursor) break;
  }
  assert.equal(new Set(served).size, served.length, "repeated content");
  assert.equal(served.length, 30, `cursor walk reached ${served.length} of 30`);
  return `30/30 at ${[...stamps][0]}`;
});

/** A small catalog in a language of its own, so no other step sees it. */
async function seedSmallCatalog(prefix, language, count) {
  const base = Date.now() - count * 1000;
  const batch = db.batch();
  const ids = [];
  for (let i = 0; i < count; i += 1) {
    const id = `${prefix}_${String(i).padStart(2, "0")}`;
    ids.push(id);
    batch.set(db.doc(`humorContent/${id}`), {
      contentId: id,
      type: "meme",
      language,
      category: "meme",
      humorTags: [],
      humorVector: {meme: 0.7},
      media: {downloadUrl: `https://example.test/${id}.png`},
      safetyStatus: "approved",
      safetyFlags: {},
      source: {type: "internal", provider: "mevora-internal", licenseRef: null},
      active: true,
      createdAt: Timestamp.fromMillis(base + i * 1000),
      stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    });
  }
  await batch.commit();
  return ids;
}

step("a cursor prefetch never re-serves what a cold start just re-offered", async () => {
  const uid = "qa_feed_held";
  await completeCalibration(uid);
  await seedSmallCatalog("hd", "de", 20);
  const languages = ["de"];
  const first = await buildHumorFeed({db, uid, languages, limit: 12});
  const rest = await buildHumorFeed({db, uid, languages, limit: 12, cursor: first.nextCursor});
  assert.equal(rest.nextCursor, null, "the pass should have ended");
  const servedIds = [...first.items, ...rest.items].map((i) => i.contentId);
  assert.equal(new Set(servedIds).size, 20);

  // Five rated, fifteen fetched but unrated: the cold start is filled by
  // re-offered items alone and hands back a top cursor.
  await markInteractions(uid, servedIds.slice(0, 5));
  const cold = await buildHumorFeed({db, uid, languages, limit: 12});
  const coldIds = cold.items.map((i) => i.contentId);
  assert.equal(coldIds.length, 12);
  assert.ok(cold.nextCursor, "three unrated items are still due");

  const prefetch = await buildHumorFeed({db, uid, languages, limit: 12, cursor: cold.nextCursor});
  const prefetchIds = prefetch.items.map((i) => i.contentId);
  for (const id of prefetchIds) {
    assert.equal(coldIds.includes(id), false, `prefetch re-served held ${id}`);
  }
  assert.deepEqual([...coldIds, ...prefetchIds].sort(), servedIds.slice(5).sort());
  return `12 re-offered cold, ${prefetchIds.length} more by cursor, 0 duplicates`;
});

// Last: the curated docs below join the catalog every later step would walk.
step("calibration reaches an unseen curated item behind a chain of seen ones", async () => {
  const uid = "qa_feed_calib_chain";
  const [open, ...covered] = ANCHOR_SLOTS;
  const chain = await seedSmallCatalog("cc", "tr", 6);
  const coveredIds = await seedSmallCatalog("cv", "tr", covered.length);
  const curate = (id, slot) =>
    db.doc(`humorContent/${id}`).set(
      {
        calibrationEligible: true,
        calibrationSlot: slot.id,
        calibrationVersion: HUMOR_CALIBRATION_VERSION,
        humorVector: {[slot.primary]: 0.9},
        category: slot.primary,
      },
      {merge: true},
    );
  await Promise.all([
    ...chain.map((id) => curate(id, open)),
    ...coveredIds.map((id, i) => curate(id, covered[i])),
  ]);
  await db.doc(`users/${uid}/humor/calibration`).set({
    version: HUMOR_CALIBRATION_VERSION,
    completedCount: coveredIds.length,
    ratedContentIds: coveredIds,
    coveredSlots: covered.map((slot) => slot.id),
    coveredDimensions: [],
    degradedCount: 0,
  });
  await markInteractions(uid, coveredIds);

  // Each candidate in turn is the only unseen one, which covers every chain
  // of skipped items the slot's rotation can meet, up to five in a row.
  for (const unseenId of chain) {
    const batch = db.batch();
    for (const id of chain) {
      const ref = db.doc(`users/${uid}/humorInteractions/${id}`);
      if (id === unseenId) {
        batch.delete(ref);
      } else {
        batch.set(ref, {contentId: id, skipped: true, rating: null});
      }
    }
    await batch.commit();
    const result = await buildHumorFeed({db, uid, languages: ["tr"], limit: 12});
    assert.equal(result.items[0]?.contentId, unseenId, `the unseen ${unseenId} was not reached`);
    assert.equal(result.items[0].calibrationStage, "anchor");
    const served = await db.getAll(
      ...result.items.map((i) => db.doc(`users/${uid}/humorInteractions/${i.contentId}`)),
    );
    assert.equal(served.some((snap) => snap.exists), false, "served a seen item");
  }
  return `${chain.length}/${chain.length} rotations reached the unseen anchor`;
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
