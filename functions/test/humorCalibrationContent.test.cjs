const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ANCHOR_SLOTS,
  CALIBRATION_TOTAL,
  HUMOR_CALIBRATION_VERSION,
  coverageDimensionsOf,
} = require("../lib/humor/calibration.js");
const {
  ANCHOR_POOL_TARGET,
  CALIBRATION_SEED,
  RETIRED_TEXT_JOKE_CONTENT_IDS,
  seedAnchorPools,
} = require("../lib/humor/calibrationSeed.js");
const calibrationSeedModule = require("../lib/humor/calibrationSeed.js");
const {buildCalibrationPoolReport} = require("../lib/humor/calibrationPoolReport.js");
const {
  INTERNAL_HUMOR_SEED,
  parseHumorContent,
  toFeedSafeContent,
  upsertHumorContentDoc,
} = require("../lib/humor/contentRepository.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");

/** Firestore double: equality filters plus doc get/set, which is all this needs. */
function makeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const snapshotOf = (path) => ({
    id: path.split("/").pop(),
    exists: store.has(path),
    data: () => store.get(path),
  });
  const docRef = (path) => ({
    path,
    id: path.split("/").pop(),
    get: async () => snapshotOf(path),
    set: async (data, options) =>
      store.set(
        path,
        options?.merge && store.has(path) ? {...store.get(path), ...data} : data,
      ),
  });
  const collectionRef = (collectionPath) => {
    const build = (filters, max) => ({
      where: (field, op, value) => build([...filters, [field, value]], max),
      orderBy: () => build(filters, max),
      startAfter: () => build(filters, max),
      select: () => build(filters, max),
      limit: (n) => build(filters, n),
      doc: (id) => docRef(`${collectionPath}/${id}`),
      get: async () => {
        const docs = [];
        const prefix = `${collectionPath}/`;
        for (const [path, data] of store.entries()) {
          if (!path.startsWith(prefix)) continue;
          if (path.slice(prefix.length).includes("/")) continue;
          if (filters.every(([f, v]) => data[f] === v)) {
            docs.push({id: path.slice(prefix.length), data: () => data});
          }
        }
        docs.sort((a, b) => (a.id < b.id ? -1 : 1));
        return {docs: max ? docs.slice(0, max) : docs, empty: docs.length === 0};
      },
    });
    return build([], undefined);
  };
  return {_store: store, doc: docRef, collection: collectionRef};
}

/** Persist the curated seed the way `seedInternalHumorContent` does. */
async function seededCatalog(overrides = {}) {
  const db = makeDb({});
  for (const item of INTERNAL_HUMOR_SEED) {
    await upsertHumorContentDoc(db, {
      ...item,
      safetyStatus: "approved",
      active: true,
    });
    const patch = overrides[item.contentId];
    if (patch) {
      const path = `humorContent/${item.contentId}`;
      db._store.set(path, {...db._store.get(path), ...patch});
    }
  }
  return db;
}

// --------------------------------------------------------------------------
// Pool structure
// --------------------------------------------------------------------------

test("every anchor slot has a rotatable pool at the curation target", () => {
  const pools = seedAnchorPools();
  assert.equal(pools.size, ANCHOR_SLOTS.length);
  for (const slot of ANCHOR_SLOTS) {
    const candidates = pools.get(slot.id) ?? [];
    assert.ok(
      candidates.length >= ANCHOR_POOL_TARGET,
      `${slot.id}: ${candidates.length} candidates, target ${ANCHOR_POOL_TARGET}`,
    );
    assert.equal(
      new Set(candidates.map((c) => c.contentId)).size,
      candidates.length,
      `${slot.id} has duplicate candidate ids`,
    );
  }
});

test("the open pool can supply adaptive and exploration without repeats", () => {
  const open = CALIBRATION_SEED.filter((item) => item.calibration.slot === null);
  const needed = CALIBRATION_TOTAL - ANCHOR_SLOTS.length;
  assert.ok(
    open.length >= needed,
    `open pool has ${open.length}, calibration needs ${needed}`,
  );
});

test("every humor dimension is measurable by some curated item", () => {
  const measured = new Set();
  for (const item of CALIBRATION_SEED) {
    for (const dim of coverageDimensionsOf(item)) {
      measured.add(dim);
    }
  }
  const missing = HUMOR_CATEGORIES.filter((dim) => !measured.has(dim));
  assert.deepEqual(missing, [], `no curated content measures: ${missing.join(", ")}`);
});

test("curated content ids are unique and provenance is explicit", () => {
  const ids = CALIBRATION_SEED.map((i) => i.contentId);
  assert.equal(new Set(ids).size, ids.length, "duplicate content id in the seed");
  for (const item of CALIBRATION_SEED) {
    // Licensed GIPHY media that Mevora hand-picked: provider-sourced, curated
    // tier, and credited to its uploader.
    assert.equal(item.provider, "giphy", item.contentId);
    assert.equal(item.sourceType, "licensed_api", item.contentId);
    assert.equal(item.sourceTrust, "curated", item.contentId);
    assert.equal(item.curatedCatalogEntry, true, item.contentId);
    assert.equal(item.attribution.provider, "giphy", item.contentId);
    assert.equal(item.contentId, `hc_gif_${item.sourceId}`);
    assert.equal(item.calibration.version, HUMOR_CALIBRATION_VERSION);
  }
});

// --------------------------------------------------------------------------
// Content integrity: one exact, credited GIPHY clip per item
// --------------------------------------------------------------------------

/** Every URL anywhere in a value. */
function urlsIn(value, out = []) {
  if (typeof value === "string") {
    if (/https?:\/\//i.test(value)) out.push(value);
  } else if (Array.isArray(value)) {
    value.forEach((v) => urlsIn(v, out));
  } else if (value && typeof value === "object") {
    Object.values(value).forEach((v) => urlsIn(v, out));
  }
  return out;
}

test("every curated item is one GIPHY clip with its own media and no caption", () => {
  // Regression guard: jokes used to be glued onto unrelated stock media ("a
  // fridge joke under a sword fight"). A curated item is now exactly one
  // thing — a clip — and everything on it belongs to that clip.
  for (const item of CALIBRATION_SEED) {
    assert.equal(item.type, "meme", `${item.contentId} is not a GIF card`);
    // Present, not absent: the seed is written with a merge, so only an
    // explicit value replaces what an older seed left on the document.
    for (const key of ["downloadUrl", "thumbUrl", "durationMs", "aspectRatio", "textBody"]) {
      assert.ok(Object.hasOwn(item.media, key), `${item.contentId} omits media.${key}`);
    }
    assert.equal(item.media.textBody, null, `${item.contentId} carries a caption`);
    assert.equal(item.media.durationMs, null, item.contentId);
    assert.ok(item.media.aspectRatio > 0, item.contentId);
    // Every URL on the item is GIPHY's, and the media are this clip's own.
    for (const url of urlsIn(item)) {
      const host = new URL(url).hostname;
      assert.ok(host === "giphy.com" || host.endsWith(".giphy.com"), `${item.contentId}: ${url}`);
    }
    for (const url of [item.media.downloadUrl, item.media.thumbUrl]) {
      assert.ok(new URL(url).pathname.split("/").includes(item.sourceId), `${item.contentId}: ${url}`);
    }
  }
});

test("the stock-media helpers are gone from the user-facing catalogue module", () => {
  assert.equal("SEED_VIDEO_CLIPS" in calibrationSeedModule, false);
  const source = require("node:fs").readFileSync(
    require("node:path").join(__dirname, "..", "src", "humor", "calibrationSeed.ts"),
    "utf8",
  );
  for (const host of ["picsum.photos", "test-videos.co.uk", "mdn.mozilla.net"]) {
    assert.equal(source.includes(host), false, `calibrationSeed.ts still references ${host}`);
  }
});

test("the catalogue keeps the calibration shape: 36 items, 6 slots x 4, open pool", () => {
  // Switching from text cards to GIFs must not move calibration: 6 slots x 4
  // candidates plus a 12-item open pool, every item calibration content.
  assert.equal(CALIBRATION_SEED.length, 36);
  assert.equal(CALIBRATION_SEED.filter((i) => i.calibration.slot !== null).length, 24);
  assert.equal(CALIBRATION_SEED.filter((i) => i.calibration.slot === null).length, 12);
  for (const item of CALIBRATION_SEED) {
    assert.equal(item.calibration.eligible, true, item.contentId);
    assert.ok(HUMOR_CATEGORIES.includes(item.category), item.contentId);
    assert.ok(Object.keys(item.humorVector).length > 0, item.contentId);
  }
});

test("only the ids of the retired text cards remain, and none is reused", () => {
  assert.equal(RETIRED_TEXT_JOKE_CONTENT_IDS.length, 36);
  assert.equal(new Set(RETIRED_TEXT_JOKE_CONTENT_IDS).size, 36);
  const active = new Set(CALIBRATION_SEED.map((i) => i.contentId));
  for (const id of RETIRED_TEXT_JOKE_CONTENT_IDS) {
    assert.match(id, /^hc_(tr|en)_(img|vid)_\d{3}$/);
    assert.equal(active.has(id), false, `${id} is back in the active catalogue`);
  }
});

test("re-seeding over a stale document ends with exactly the clip, uncaptioned", async () => {
  // Real merge semantics: `set(..., {merge: true})` deep-merges maps, so a
  // missing key would keep an old value. The fake deep-merges like Firestore.
  const db = createFakeFirestore({});
  const seed = seedAnchorPools().get("anchor_everyday")[0];
  db.reset({
    [`humorContent/${seed.contentId}`]: {
      contentId: seed.contentId,
      type: "video",
      language: "tr",
      category: "situational",
      humorTags: ["legacy"],
      humorVector: {situational: 0.86},
      media: {
        downloadUrl: "https://media.giphy.com/media/Other123/giphy.mp4",
        thumbUrl: "https://media.giphy.com/media/Other123/200_s.gif",
        durationMs: 10000,
        aspectRatio: 0.5625,
        textBody: "Epic Fail",
        storagePath: "legacy/path.gif",
      },
      safetyStatus: "approved",
      active: true,
      source: {type: "licensed_api", provider: "giphy", licenseRef: null},
      sourceTrust: "provider",
      stats: {viewCount: 4, ratingCount: 3, avgRating: 0.5, ratingSum: 1.5},
    },
  });

  await upsertHumorContentDoc(db, {...seed, safetyStatus: "approved", active: true});

  const stored = db.read(`humorContent/${seed.contentId}`);
  assert.equal(stored.type, "meme");
  assert.deepEqual(stored.media, {
    storagePath: null,
    downloadUrl: seed.media.downloadUrl,
    thumbUrl: seed.media.thumbUrl,
    durationMs: null,
    aspectRatio: seed.media.aspectRatio,
    textBody: null,
  });
  assert.equal(stored.sourceTrust, "curated");
  assert.deepEqual(stored.attribution, seed.attribution);
  // Ratings and calibration curation survive the refresh.
  assert.equal(stored.stats.ratingCount, 3);
  assert.equal(stored.calibrationEligible, true);
  assert.equal(stored.calibrationSlot, "anchor_everyday");

  const card = toFeedSafeContent(parseHumorContent(seed.contentId, stored));
  assert.equal(card.type, "meme");
  assert.equal(card.media.downloadUrl, seed.media.downloadUrl);
  assert.equal(card.media.thumbUrl, seed.media.thumbUrl);
  assert.equal(card.media.textBody, null);
  assert.deepEqual(card.attribution, seed.attribution);

  // Idempotent: a second run changes nothing but the timestamp.
  await upsertHumorContentDoc(db, {...seed, safetyStatus: "approved", active: true});
  const again = db.read(`humorContent/${seed.contentId}`);
  assert.deepEqual({...again, updatedAt: null}, {...stored, updatedAt: null});
});

test("a text upsert drops media even when the caller passes some", async () => {
  const db = createFakeFirestore({});
  await upsertHumorContentDoc(db, {
    contentId: "hc_admin_text",
    type: "text",
    language: "tr",
    category: "dry",
    humorVector: {dry: 0.8},
    media: {
      downloadUrl: "https://media.giphy.com/media/x/giphy.mp4",
      thumbUrl: "https://media.giphy.com/media/x/200_s.gif",
      textBody: "Evet.",
    },
    safetyStatus: "approved",
    active: true,
  });
  const stored = db.read("humorContent/hc_admin_text");
  assert.equal(stored.media.downloadUrl, null);
  assert.equal(stored.media.thumbUrl, null);
  assert.equal(stored.media.textBody, "Evet.");
});

// --------------------------------------------------------------------------
// Curation boundaries
// --------------------------------------------------------------------------

test("an anchor slot tag on non-eligible content is ignored on write", async () => {
  const db = makeDb({});
  // Provider-shaped content asking to be an anchor.
  const doc = await upsertHumorContentDoc(db, {
    contentId: "ext_giphy_pretender",
    type: "video",
    language: "tr",
    category: "meme",
    humorVector: {meme: 0.9},
    safetyStatus: "approved",
    active: true,
    sourceType: "licensed_api",
    provider: "giphy",
    calibration: {eligible: false, slot: "anchor_meme"},
  });
  assert.equal(doc.calibration.eligible, false);
  assert.equal(doc.calibration.slot, null, "uncurated content claimed an anchor slot");
  const stored = db._store.get("humorContent/ext_giphy_pretender");
  assert.equal(stored.calibrationEligible, false);
  assert.equal(stored.calibrationSlot, null);
});

test("unapproved content cannot be curated, even by an admin write", async () => {
  const db = makeDb({});
  const doc = await upsertHumorContentDoc(db, {
    contentId: "hc_pending",
    type: "meme",
    language: "tr",
    category: "sarcasm",
    humorVector: {sarcasm: 0.9},
    safetyStatus: "needs_review",
    active: true,
    calibration: {eligible: true, slot: "anchor_wit"},
  });
  assert.equal(
    doc.calibration.eligible,
    false,
    "content awaiting moderation entered a calibration pool",
  );
  assert.equal(doc.calibration.slot, null);
});

test("an unknown slot id does not silently become a valid anchor", async () => {
  const db = makeDb({});
  const doc = await upsertHumorContentDoc(db, {
    contentId: "hc_typo_slot",
    type: "meme",
    language: "tr",
    category: "sarcasm",
    humorVector: {sarcasm: 0.9},
    safetyStatus: "approved",
    active: true,
    calibration: {eligible: true, slot: "anchor_wtt"},
  });
  assert.equal(doc.calibration.eligible, true, "still ordinary calibration content");
  assert.equal(doc.calibration.slot, null, "a typo must not create a phantom slot");
});

// --------------------------------------------------------------------------
// Pool health report
// --------------------------------------------------------------------------

test("the pool report calls a fully curated catalog healthy", async () => {
  const db = await seededCatalog();
  const report = await buildCalibrationPoolReport(db);

  assert.equal(report.calibrationVersion, HUMOR_CALIBRATION_VERSION);
  assert.equal(report.healthy, true, report.warnings.join("; "));
  assert.deepEqual(report.warnings, []);
  assert.equal(report.anchorSlots.length, ANCHOR_SLOTS.length);
  for (const slot of report.anchorSlots) {
    assert.equal(slot.ok, true, `${slot.slotId}: ${slot.warnings.join("; ")}`);
    assert.ok(slot.measuring >= ANCHOR_POOL_TARGET, slot.slotId);
    assert.equal(slot.candidates, slot.measuring, `${slot.slotId} has mistagged content`);
  }
  assert.deepEqual(report.uncoveredDimensions, []);
  assert.deepEqual(
    report.guaranteedAnchorCoverage,
    [...ANCHOR_SLOTS.map((s) => s.primary)].sort(),
  );
  assert.ok(report.openPoolSize >= CALIBRATION_TOTAL - ANCHOR_SLOTS.length);
});

test("the pool report names the slot when a pool is emptied", async () => {
  const starved = {};
  for (const item of seedAnchorPools().get("anchor_social") ?? []) {
    starved[item.contentId] = {calibrationSlot: null, calibrationEligible: false};
  }
  const db = await seededCatalog(starved);
  const report = await buildCalibrationPoolReport(db);

  assert.equal(report.healthy, false);
  const social = report.anchorSlots.find((s) => s.slotId === "anchor_social");
  assert.equal(social.candidates, 0);
  assert.equal(social.ok, false);
  assert.ok(
    report.warnings.some((w) => w.includes("anchor_social")),
    `warnings did not name the empty slot: ${report.warnings.join("; ")}`,
  );
});

test("the pool report flags a slot that cannot rotate", async () => {
  const candidates = seedAnchorPools().get("anchor_wit") ?? [];
  const starved = {};
  for (const item of candidates.slice(1)) {
    starved[item.contentId] = {calibrationEligible: false, calibrationSlot: null};
  }
  const db = await seededCatalog(starved);
  const report = await buildCalibrationPoolReport(db);

  const wit = report.anchorSlots.find((s) => s.slotId === "anchor_wit");
  assert.equal(wit.measuring, 1);
  assert.equal(wit.ok, false);
  assert.ok(
    wit.warnings.some((w) => w.includes("rotate")),
    `expected a rotation warning, got: ${wit.warnings.join("; ")}`,
  );
});

test("the pool report ignores inactive and unapproved content", async () => {
  const first = (seedAnchorPools().get("anchor_meme") ?? [])[0];
  const db = await seededCatalog({[first.contentId]: {active: false}});
  const report = await buildCalibrationPoolReport(db);

  const meme = report.anchorSlots.find((s) => s.slotId === "anchor_meme");
  assert.equal(
    meme.candidates,
    ANCHOR_POOL_TARGET - 1,
    "an inactive item was still counted as an available candidate",
  );
});
