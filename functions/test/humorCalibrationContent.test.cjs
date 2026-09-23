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
  QA_SEED_PROVIDER,
  seedAnchorPools,
} = require("../lib/humor/calibrationSeed.js");
const {buildCalibrationPoolReport} = require("../lib/humor/calibrationPoolReport.js");
const {
  INTERNAL_HUMOR_SEED,
  upsertHumorContentDoc,
} = require("../lib/humor/contentRepository.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");

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
    assert.equal(
      item.provider,
      QA_SEED_PROVIDER,
      `${item.contentId} does not declare QA-tier provenance`,
    );
    assert.equal(item.sourceType, "internal");
    assert.equal(item.calibration.version, HUMOR_CALIBRATION_VERSION);
  }
});

test("curated media is https and comes from permitted hosts only", () => {
  const allowed = ["commondatastorage.googleapis.com", "picsum.photos"];
  for (const item of CALIBRATION_SEED) {
    for (const url of [item.media.downloadUrl, item.media.thumbUrl]) {
      assert.ok(url.startsWith("https://"), `${item.contentId}: ${url}`);
      const host = new URL(url).hostname;
      assert.ok(
        allowed.includes(host),
        `${item.contentId} uses an unapproved host: ${host}`,
      );
    }
    assert.ok(item.media.textBody.trim().length > 0, `${item.contentId} has no caption`);
  }
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
