const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ANCHOR_SLOTS,
  ANCHOR_INTERACTIONS,
  ADAPTIVE_INTERACTIONS,
  EXPLORATION_INTERACTIONS,
  CALIBRATION_TOTAL,
  HUMOR_CALIBRATION_VERSION,
  advanceCalibration,
  coverageDimensionsOf,
  defaultCalibrationState,
  isAnchorSlotId,
  isCalibrationComplete,
  parseCalibrationState,
  stageForCompletedCount,
  toCalibrationView,
} = require("../lib/humor/calibration.js");
const {HUMOR_CORE_SEQUENCE} = require("../lib/humor/coreSequence.js");
const {
  INTERNAL_HUMOR_SEED,
  parseCalibrationMeta,
  parseHumorContent,
  listCalibrationPool,
} = require("../lib/humor/contentRepository.js");
const {submitHumorFeedbackTx} = require("../lib/humor/feedback.js");
const {humorScoreForPair} = require("../lib/humor/compatibility.js");
const {
  applyFeedbackToProfile,
  defaultUserHumorProfile,
} = require("../lib/humor/profile.js");
const {emptyHumorVector} = require("../lib/humor/categories.js");

// --------------------------------------------------------------------------
// Minimal in-memory Firestore double. Supports only what the humor modules
// actually call: doc get/set, equality-filtered collection queries, and a
// non-isolated runTransaction (enough to assert read-modify-write ordering).
// --------------------------------------------------------------------------

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    (value.constructor === Object || value.constructor === undefined)
  );
}

/** A resolved `FieldValue.increment(operand)`. */
class Increment {
  constructor(operand) {
    this.operand = operand;
  }
}

/**
 * FieldValue sentinels are opaque here and replaced by a marker, except
 * `FieldValue.increment`, which the stats update relies on for exactness.
 */
function sanitize(value) {
  if (Array.isArray(value)) {
    return value.map(sanitize);
  }
  if (isPlainObject(value)) {
    const out = {};
    for (const [key, inner] of Object.entries(value)) {
      out[key] = sanitize(inner);
    }
    return out;
  }
  if (value !== null && typeof value === "object") {
    if (value.constructor && value.constructor.name === "NumericIncrementTransform") {
      return new Increment(value.operand);
    }
    return "<sentinel>";
  }
  return value;
}

function mergeInto(target, patch) {
  const out = {...target};
  for (const [key, value] of Object.entries(patch)) {
    if (value instanceof Increment) {
      out[key] = (typeof out[key] === "number" ? out[key] : 0) + value.operand;
    } else if (isPlainObject(value)) {
      out[key] = mergeInto(isPlainObject(out[key]) ? out[key] : {}, value);
    } else {
      out[key] = value;
    }
  }
  return out;
}

/** `update()` semantics: dotted field paths, and the document must exist. */
function applyUpdate(target, patch) {
  let out = target;
  for (const [fieldPath, value] of Object.entries(patch)) {
    const segments = fieldPath.split(".");
    const nested = {};
    let cursor = nested;
    segments.slice(0, -1).forEach((segment) => {
      cursor[segment] = {};
      cursor = cursor[segment];
    });
    cursor[segments[segments.length - 1]] = value;
    out = mergeInto(out, nested);
  }
  return out;
}

function makeDb(initial = {}) {
  const store = new Map(Object.entries(initial).map(([k, v]) => [k, sanitize(v)]));
  const writes = [];

  const snapshotOf = (path) => ({
    id: path.split("/").pop(),
    exists: store.has(path),
    data: () => (store.has(path) ? store.get(path) : undefined),
  });

  const write = (path, data, options) => {
    writes.push(path);
    const clean = sanitize(data);
    store.set(
      path,
      mergeInto(options && options.merge && store.has(path) ? store.get(path) : {}, clean),
    );
  };

  const docRef = (path) => ({
    path,
    id: path.split("/").pop(),
    get: async () => snapshotOf(path),
    set: async (data, options) => write(path, data, options),
    update: async (data) => {
      if (!store.has(path)) {
        throw new Error(`NOT_FOUND: ${path}`);
      }
      writes.push(path);
      store.set(path, applyUpdate(store.get(path), sanitize(data)));
    },
    delete: async () => store.delete(path),
  });

  const collectionRef = (collectionPath) => {
    const build = (filters, max) => ({
      where: (field, op, value) => {
        assert.equal(op, "==", "stub only implements equality filters");
        return build([...filters, [field, value]], max);
      },
      select: () => build(filters, max),
      limit: (n) => build(filters, n),
      get: async () => {
        const docs = [];
        for (const [path, data] of store.entries()) {
          const prefix = `${collectionPath}/`;
          if (!path.startsWith(prefix)) continue;
          if (path.slice(prefix.length).includes("/")) continue;
          if (filters.every(([field, value]) => data[field] === value)) {
            docs.push({id: path.slice(prefix.length), data: () => data});
          }
        }
        docs.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
        return {docs: max ? docs.slice(0, max) : docs, empty: docs.length === 0};
      },
      doc: (id) => docRef(`${collectionPath}/${id}`),
    });
    return build([], undefined);
  };

  return {
    _store: store,
    _writes: writes,
    doc: docRef,
    collection: collectionRef,
    getAll: async (...refs) => refs.map((ref) => snapshotOf(ref.path)),
    runTransaction: async (fn) =>
      fn({
        get: async (ref) => snapshotOf(ref.path),
        set: (ref, data, options) => write(ref.path, data, options),
      }),
  };
}

/** Shape a seed entry the way `upsertHumorContentDoc` would persist it. */
function seedDocFrom(item) {
  return {
    contentId: item.contentId,
    type: item.type,
    language: item.language,
    category: item.category,
    humorTags: item.humorTags ?? [],
    humorVector: item.humorVector,
    media: item.media ?? {},
    safetyStatus: "approved",
    safetyFlags: {},
    source: {type: "internal", provider: "mevora-internal", licenseRef: null},
    calibrationEligible: item.calibration?.eligible === true,
    calibrationSlot: item.calibration?.slot ?? null,
    calibrationVersion:
      item.calibration?.eligible === true ? HUMOR_CALIBRATION_VERSION : 0,
    active: true,
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
  };
}

function seededDb(overrides = {}) {
  const docs = {};
  for (const item of INTERNAL_HUMOR_SEED) {
    docs[`humorContent/${item.contentId}`] = {
      ...seedDocFrom(item),
      ...(overrides[item.contentId] ?? {}),
    };
  }
  return makeDb(docs);
}

/** The curated catalogue's anchor candidates for a slot, in catalogue order. */
const {seedAnchorPools: curatedAnchorPools} = require("../lib/humor/calibrationSeed.js");
function anchorIdOf(slotId, index = 0) {
  return curatedAnchorPools().get(slotId)[index].contentId;
}

// --------------------------------------------------------------------------
// Stage contract
// --------------------------------------------------------------------------

test("the calibration milestone keeps its stage boundaries: 6 + 6 + 3 = 15", () => {
  assert.equal(ANCHOR_INTERACTIONS, 6);
  assert.equal(ADAPTIVE_INTERACTIONS, 6);
  assert.equal(EXPLORATION_INTERACTIONS, 3);
  assert.equal(CALIBRATION_TOTAL, 15);
  assert.equal(ANCHOR_SLOTS.length, ANCHOR_INTERACTIONS);
  assert.equal(new Set(ANCHOR_SLOTS.map((s) => s.id)).size, ANCHOR_INTERACTIONS);
});

test("stage transitions land exactly on the boundaries", () => {
  const stages = [];
  for (let i = 0; i <= CALIBRATION_TOTAL; i += 1) {
    stages.push(stageForCompletedCount(i));
  }
  assert.deepEqual(stages, [
    "anchor", "anchor", "anchor", "anchor", "anchor", "anchor",
    "adaptive", "adaptive", "adaptive", "adaptive", "adaptive", "adaptive",
    "exploration", "exploration", "exploration",
    "complete",
  ]);
  assert.equal(isCalibrationComplete(14), false);
  assert.equal(isCalibrationComplete(15), true);
  // Out-of-range input cannot produce a stage outside the contract.
  assert.equal(stageForCompletedCount(-3), "anchor");
  assert.equal(stageForCompletedCount(999), "complete");
});

test("client-facing view exposes progress but no internals", () => {
  const view = toCalibrationView({version: 1, completedCount: 7});
  assert.deepEqual(Object.keys(view).sort(), [
    "complete",
    "completedCount",
    "degraded",
    "stage",
    "totalCount",
    "version",
  ]);
  assert.equal(view.stage, "adaptive");
  assert.equal(view.totalCount, 15);
  assert.equal(view.complete, false);
  // QA-only quality flag: a boolean, never the count or what degraded.
  assert.equal(view.degraded, false);
  assert.equal(
    toCalibrationView({version: 1, completedCount: 7, degradedCount: 2}).degraded,
    true,
  );
  // Over-count is clamped rather than leaking a bogus number to the client.
  assert.equal(toCalibrationView({version: 1, completedCount: 99}).completedCount, 15);
});

// --------------------------------------------------------------------------
// Versioning
// --------------------------------------------------------------------------

test("a foreign calibration version restarts instead of corrupting coverage", () => {
  const current = parseCalibrationState({
    version: HUMOR_CALIBRATION_VERSION,
    completedCount: 9,
    ratedContentIds: ["a", "b"],
    coveredSlots: ["anchor_wit"],
    coveredDimensions: ["sarcasm"],
  });
  assert.equal(current.completedCount, 9);
  assert.equal(current.stage, "adaptive");
  assert.deepEqual(current.coveredSlots, ["anchor_wit"]);

  const foreign = parseCalibrationState({
    version: HUMOR_CALIBRATION_VERSION + 1,
    completedCount: 9,
    ratedContentIds: ["a", "b"],
    coveredSlots: ["anchor_wit"],
  });
  assert.deepEqual(foreign, defaultCalibrationState());

  assert.deepEqual(parseCalibrationState(undefined), defaultCalibrationState());
});

// --------------------------------------------------------------------------
// State advance
// --------------------------------------------------------------------------

function contentFor(id, vector, calibration) {
  return {
    contentId: id,
    category: "meme",
    humorVector: {...emptyHumorVector(0), ...vector},
    calibration: calibration ?? {eligible: false, slot: null, version: 0},
  };
}

test("advance records coverage, stops at 15 and is idempotent", () => {
  let state = defaultCalibrationState();
  assert.equal(state.completedCount, 0);
  assert.equal(state.version, HUMOR_CALIBRATION_VERSION);

  state = advanceCalibration({
    state,
    content: contentFor("c1", {sarcasm: 0.9}, {
      eligible: true,
      slot: "anchor_wit",
      version: HUMOR_CALIBRATION_VERSION,
    }),
  });
  assert.equal(state.completedCount, 1);
  assert.deepEqual(state.coveredSlots, ["anchor_wit"]);
  assert.deepEqual(state.coveredDimensions, ["sarcasm"]);
  assert.equal(state.degradedCount, 0);

  // Same content again must not double-count.
  const repeated = advanceCalibration({
    state,
    content: contentFor("c1", {sarcasm: 0.9}, {
      eligible: true,
      slot: "anchor_wit",
      version: HUMOR_CALIBRATION_VERSION,
    }),
  });
  assert.equal(repeated.completedCount, 1);

  // Uncurated content never claims an anchor position while curated
  // candidates remain…
  const uncurated = contentFor("c2", {meme: 0.8}, {
    eligible: false,
    slot: "anchor_meme",
    version: 0,
  });
  assert.equal(advanceCalibration({state, content: uncurated}), state);

  // …and when the pool is exhausted it fills the position as a recorded
  // degradation, without a slot and without coverage.
  state = advanceCalibration({state, content: uncurated, allowUncuratedAnchor: true});
  assert.equal(state.completedCount, 2);
  assert.deepEqual(state.coveredSlots, ["anchor_wit"]);
  assert.deepEqual(state.coveredDimensions, ["sarcasm"]);
  assert.equal(state.degradedCount, 1);

  // A curated item that measures no new slot is a degraded *anchor* position.
  state = advanceCalibration({
    state,
    content: contentFor("c2b", {sarcasm: 0.85}, {
      eligible: true,
      slot: "anchor_wit",
      version: HUMOR_CALIBRATION_VERSION,
    }),
  });
  assert.equal(state.completedCount, 3);
  assert.equal(state.degradedCount, 2);

  const curatedPool = {eligible: true, slot: null, version: HUMOR_CALIBRATION_VERSION};
  for (let i = 3; i <= 20; i += 1) {
    state = advanceCalibration({
      state,
      content: contentFor(`c${i}`, {silly: 0.7}, curatedPool),
    });
  }
  assert.equal(state.completedCount, CALIBRATION_TOTAL);
  assert.equal(state.complete, true);
  assert.equal(state.stage, "complete");
  assert.equal(state.ratedContentIds.length, CALIBRATION_TOTAL);
});

test("coverage needs real vector mass, not just a declared category", () => {
  assert.deepEqual(coverageDimensionsOf({humorVector: {sarcasm: 0.9, dry: 0.2}, category: "meme"}), [
    "sarcasm",
  ]);
  // Vector-less curated content still measures its declared category.
  assert.deepEqual(coverageDimensionsOf({humorVector: {}, category: "wordplay"}), [
    "wordplay",
  ]);
});

// --------------------------------------------------------------------------
// Content curation
// --------------------------------------------------------------------------

test("calibration metadata is closed by default", () => {
  assert.deepEqual(parseCalibrationMeta({}), {
    eligible: false,
    slot: null,
    version: 0,
  });
  // A slot on a non-eligible document is ignored: uncurated provider content
  // cannot present itself as an anchor.
  assert.deepEqual(
    parseCalibrationMeta({calibrationSlot: "anchor_wit", calibrationVersion: 1}),
    {eligible: false, slot: null, version: 1},
  );
  assert.deepEqual(
    parseCalibrationMeta({
      calibrationEligible: true,
      calibrationSlot: "anchor_wit",
      calibrationVersion: 1,
    }),
    {eligible: true, slot: "anchor_wit", version: 1},
  );
  assert.equal(isAnchorSlotId("anchor_wit"), true);
  assert.equal(isAnchorSlotId("anchor_nope"), false);
});

test("internal seed covers every anchor slot with a rotatable pool", () => {
  const bySlot = new Map();
  for (const item of INTERNAL_HUMOR_SEED) {
    if (item.calibration?.eligible && item.calibration.slot) {
      bySlot.set(item.calibration.slot, (bySlot.get(item.calibration.slot) ?? 0) + 1);
    }
  }
  for (const slot of ANCHOR_SLOTS) {
    assert.ok(
      (bySlot.get(slot.id) ?? 0) >= 2,
      `slot ${slot.id} needs at least two equivalent candidates`,
    );
  }
  // Everything curated must declare a real slot or an explicit null.
  for (const item of INTERNAL_HUMOR_SEED) {
    if (item.calibration?.eligible && item.calibration.slot !== null) {
      assert.ok(isAnchorSlotId(item.calibration.slot), item.contentId);
    }
  }
});

test("every anchor candidate measures its slot primary, on every rotation", async () => {
  // Comparability is the whole point of the anchor stage. Deeper pools mean
  // candidates no longer share *incidental* secondary dimensions, so the
  // guarantee has to be the thing each slot was designed to measure: its
  // primary. That set is the comparable baseline two profiles share.
  const {
    seedAnchorPools,
    ANCHOR_POOL_TARGET,
  } = require("../lib/humor/calibrationSeed.js");
  const pools = seedAnchorPools();

  for (const slot of ANCHOR_SLOTS) {
    const candidates = pools.get(slot.id) ?? [];
    assert.ok(
      candidates.length >= ANCHOR_POOL_TARGET,
      `${slot.id} has ${candidates.length} candidates, target is ${ANCHOR_POOL_TARGET}`,
    );
    for (const candidate of candidates) {
      assert.ok(
        coverageDimensionsOf(candidate).includes(slot.primary),
        `${candidate.contentId} is tagged ${slot.id} but does not measure ${slot.primary}`,
      );
    }
  }

  const depth = Math.max(...[...pools.values()].map((p) => p.length));
  const paths = [];
  for (let pick = 0; pick < depth; pick += 1) {
    const dims = new Set();
    for (const slot of ANCHOR_SLOTS) {
      const pool = [...(pools.get(slot.id) ?? [])].sort((a, b) =>
        a.contentId < b.contentId ? -1 : 1,
      );
      for (const dim of coverageDimensionsOf(pool[pick % pool.length])) {
        dims.add(dim);
      }
    }
    paths.push([...dims].sort());
  }

  const guaranteed = paths[0].filter((dim) => paths.every((p) => p.includes(dim)));
  assert.deepEqual(
    guaranteed,
    [...ANCHOR_SLOTS.map((s) => s.primary)].sort(),
    "the guaranteed comparable baseline must be exactly the slot primaries",
  );
  assert.deepEqual(guaranteed, [
    "absurd",
    "cringe",
    "meme",
    "sarcasm",
    "situational",
    "wordplay",
  ]);

  // romantic and dark stay out of the baseline by design.
  assert.equal(guaranteed.includes("romantic"), false);
  assert.equal(guaranteed.includes("dark"), false);
});

test("pool query excludes inactive, unapproved and uncurated content", async () => {
  const inactive = anchorIdOf("anchor_wit");
  const unapproved = anchorIdOf("anchor_absurd");
  const uncurated = anchorIdOf("anchor_wordplay");
  const foreignVersion = anchorIdOf("anchor_everyday");
  const db = seededDb({
    [inactive]: {active: false},
    [unapproved]: {safetyStatus: "needs_review"},
    [uncurated]: {calibrationEligible: false, calibrationSlot: "anchor_wordplay"},
    [foreignVersion]: {calibrationVersion: 99},
  });
  const pool = await listCalibrationPool(db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });
  const ids = pool.map((item) => item.contentId);
  assert.equal(ids.includes(inactive), false, "inactive excluded");
  assert.equal(ids.includes(unapproved), false, "unapproved excluded");
  assert.equal(ids.includes(uncurated), false, "uncurated excluded");
  assert.equal(ids.includes(foreignVersion), false, "foreign version excluded");
  // Exactly those four — everything else in the catalogue is served.
  assert.equal(ids.length, INTERNAL_HUMOR_SEED.length - 4);
});

// --------------------------------------------------------------------------
// Feedback transaction: completion + lifetime learning
// --------------------------------------------------------------------------

async function rate(db, uid, contentId, rating) {
  return submitHumorFeedbackTx({db, uid, contentId, rating});
}

test("calibration completes on the 15th rating and learning continues after", async () => {
  const uid = "user_lifetime";
  const db = seededDb();
  const ids = INTERNAL_HUMOR_SEED.map((item) => item.contentId);
  assert.ok(ids.length >= 16, "seed must supply more content than calibration needs");

  let result;
  for (let i = 0; i < CALIBRATION_TOTAL; i += 1) {
    result = await rate(db, uid, ids[i], i % 2 === 0 ? "very_funny" : "funny");
    assert.equal(result.calibration.completedCount, i + 1);
    assert.equal(result.calibration.version, HUMOR_CALIBRATION_VERSION);
    assert.equal(result.interactionCount, i + 1);
  }
  assert.equal(result.calibration.complete, true);
  assert.equal(result.calibration.stage, "complete");
  assert.equal(result.profileBuilding, false, "calibration done ⇒ no longer building");

  const atCompletion = {
    interactionCount: result.interactionCount,
    confidence: result.confidence,
  };

  // Interaction 16+ — the lifetime profile must keep moving.
  const after = await rate(db, uid, ids[15], "very_funny");
  assert.equal(after.interactionCount, atCompletion.interactionCount + 1);
  assert.ok(
    after.confidence > atCompletion.confidence,
    "confidence must keep growing after calibration",
  );
  assert.equal(after.calibration.completedCount, CALIBRATION_TOTAL);
  assert.equal(after.calibration.complete, true);
  assert.equal(after.profileBuilding, false);

  const summary = db._store.get(`users/${uid}/humor/summary`);
  assert.equal(summary.interactionCount, 16);
  assert.ok(summary.exploredCategories.length > 0);

  const persisted = db._store.get(`users/${uid}/humor/calibration`);
  assert.equal(persisted.completedCount, CALIBRATION_TOTAL);
  assert.equal(persisted.complete, true);
  assert.equal(persisted.ratedContentIds.length, CALIBRATION_TOTAL);
});

test("re-rating the same content never inflates calibration", async () => {
  const uid = "user_rerate";
  const db = seededDb();
  const id = INTERNAL_HUMOR_SEED[0].contentId;

  const first = await rate(db, uid, id, "funny");
  assert.equal(first.calibration.completedCount, 1);

  const changed = await rate(db, uid, id, "not_funny");
  assert.equal(changed.calibration.completedCount, 1, "same content, same position");
  assert.equal(changed.interactionCount, 1);

  const other = await rate(db, uid, INTERNAL_HUMOR_SEED[1].contentId, "funny");
  assert.equal(other.calibration.completedCount, 2);
});

test("calibration state survives a reload of the persisted document", async () => {
  const uid = "user_restart";
  const db = seededDb();
  const ids = INTERNAL_HUMOR_SEED.map((item) => item.contentId);
  for (let i = 0; i < 7; i += 1) {
    await rate(db, uid, ids[i], "funny");
  }

  // Simulate a cold start: nothing but the stored document is available.
  const reloaded = parseCalibrationState(
    db._store.get(`users/${uid}/humor/calibration`),
  );
  assert.equal(reloaded.completedCount, 7);
  assert.equal(reloaded.stage, "adaptive");
  assert.equal(reloaded.complete, false);
  assert.equal(reloaded.ratedContentIds.length, 7);

  const next = await rate(db, uid, ids[7], "funny");
  assert.equal(next.calibration.completedCount, 8);
  assert.equal(next.calibration.stage, "adaptive");
});

// --------------------------------------------------------------------------
// Privacy: account deletion
// --------------------------------------------------------------------------

test("calibration state is swept by the existing account deletion path", async () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const {HUMOR_CALIBRATION_DOC} = require("../lib/humor/feed.js");

  // The document deliberately lives inside the `users/{uid}/humor` collection
  // so it inherits the existing deletion sweep and the existing owner-read
  // rule instead of needing new ones.
  assert.equal(HUMOR_CALIBRATION_DOC("u1"), "users/u1/humor/calibration");

  const uid = "user_deleted";
  const db = seededDb();
  const ids = INTERNAL_HUMOR_SEED.map((item) => item.contentId);
  for (let i = 0; i < 4; i += 1) {
    await rate(db, uid, ids[i], "funny");
  }
  assert.ok(db._store.has(`users/${uid}/humor/calibration`));
  assert.ok(db._store.has(`users/${uid}/humor/summary`));

  // Replay what `deleteCollectionDocs('users/{uid}/humor')` does.
  const snap = await db.collection(`users/${uid}/humor`).get();
  const sweptIds = snap.docs.map((d) => d.id).sort();
  assert.deepEqual(sweptIds, ["calibration", "summary"]);
  for (const doc of snap.docs) {
    db._store.delete(`users/${uid}/humor/${doc.id}`);
  }
  assert.equal(db._store.has(`users/${uid}/humor/calibration`), false);

  // Guard the sweep itself: if this line ever disappears, calibration state
  // would survive an account deletion.
  const source = fs.readFileSync(
    path.join(__dirname, "..", "src", "deleteAccount.ts"),
    "utf8",
  );
  assert.ok(
    source.includes("deleteCollectionDocs(`users/${uid}/humor`)"),
    "deleteAccount must still sweep the users/{uid}/humor collection",
  );
});

// --------------------------------------------------------------------------
// Untouched neighbours
// --------------------------------------------------------------------------

test("standalone humor compatibility is unchanged by calibration", () => {
  const building = humorScoreForPair(
    {...defaultUserHumorProfile(), interactionCount: 3, confidence: 0.05},
    {...defaultUserHumorProfile(), interactionCount: 3, confidence: 0.05},
  );
  assert.equal(building.available, false);
  assert.equal(building.reason, "building");

  const ready = {
    ...defaultUserHumorProfile(),
    vector: {...emptyHumorVector(50), sarcasm: 88, dry: 80},
    interactionCount: 20,
    confidence: 0.6,
  };
  const scored = humorScoreForPair(ready, ready);
  assert.equal(scored.available, true);
  assert.ok(scored.score >= 0 && scored.score <= 100);
  // Calibration adds no field to this contract.
  assert.equal("calibration" in scored, false);
});

test("feed-safe content carries the stage but never the slot or safety data", () => {
  const {toFeedSafeContent} = require("../lib/humor/contentRepository.js");
  const id = anchorIdOf("anchor_wit");
  const doc = parseHumorContent(id, {
    ...seedDocFrom(INTERNAL_HUMOR_SEED.find((i) => i.contentId === id)),
  });
  const safe = toFeedSafeContent(doc, "anchor");
  assert.equal(safe.calibrationStage, "anchor");
  assert.equal("calibrationSlot" in safe, false);
  assert.equal("humorVector" in safe, false);
  assert.equal("safetyFlags" in safe, false);
  assert.equal("safetyStatus" in safe, false);
  assert.equal(toFeedSafeContent(doc).calibrationStage, null);
});

// --------------------------------------------------------------------------
// Engine behaviour end to end: personas through the canonical first fifteen
// (the Core sequence every member rates) and the real feedback transaction
// --------------------------------------------------------------------------

const {
  loadUserHumorCalibration,
  loadUserHumorProfile,
} = require("../lib/humor/feed.js");
const {
  parseSubmitHumorFeedbackInput,
} = require("../lib/humor/feedback.js");
const {learningRate, YOUNG_LEARNING_RATE} = require("../lib/humor/profile.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");

const seedById = new Map(INTERNAL_HUMOR_SEED.map((item) => [item.contentId, item]));

/**
 * A user with fixed taste: `taste[dim]` in -1..1, everything else 0. They
 * judge an item by its mass-weighted taste, so an item that is only partly
 * their style gets a milder answer — the way people actually rate.
 */
function persona(taste) {
  return (content) => {
    let num = 0;
    let den = 0;
    for (const dim of HUMOR_CATEGORIES) {
      const mass = content.humorVector[dim] ?? 0;
      if (mass > 0) {
        num += mass * (taste[dim] ?? 0);
        den += mass;
      }
    }
    const score = den > 0 ? num / den : 0;
    if (score >= 0.45) return "very_funny";
    if (score >= 0.15) return "funny";
    if (score > -0.15) return "neutral";
    if (score > -0.45) return "not_funny";
    return "not_at_all";
  };
}

/** Deterministic PRNG for the noise personas. */
function lcg(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

async function interactedIds(db, uid) {
  const snap = await db.collection(`users/${uid}/humorInteractions`).get();
  return new Set(snap.docs.map((d) => d.id));
}

/**
 * V1–V15 in canonical order, each rated through submitHumorFeedbackTx — what
 * a member's initial calibration is.
 */
async function calibrateThroughServer(db, uid, rateFor) {
  const picks = [];
  const progress = [];
  for (const entry of HUMOR_CORE_SEQUENCE.slice(0, CALIBRATION_TOTAL)) {
    const content = parseHumorContent(entry.id, db._store.get(`humorContent/${entry.id}`));
    const result = await submitHumorFeedbackTx({
      db,
      uid,
      contentId: entry.id,
      rating: rateFor(content),
    });
    picks.push({content});
    progress.push(result.calibration.completedCount);
  }
  const summary = db._store.get(`users/${uid}/humor/summary`);
  const calibration = db._store.get(`users/${uid}/humor/calibration`);
  return {picks, progress, summary, calibration, vector: summary.vector};
}

function strongest(vector) {
  return HUMOR_CATEGORIES.reduce((a, b) => (vector[b] > vector[a] ? b : a));
}

function weakest(vector) {
  return HUMOR_CATEGORIES.reduce((a, b) => (vector[b] < vector[a] ? b : a));
}

const PERSONAS = [
  {uid: "persona_sarcasm", loves: "sarcasm", dislikes: "silly"},
  {uid: "persona_absurd", loves: "absurd", dislikes: "cringe"},
  {uid: "persona_meme", loves: "meme", dislikes: "dark"},
  {uid: "persona_wordplay", loves: "wordplay", dislikes: "sarcasm"},
];

test("a consistent persona gets a visible profile from the 15 calibration ratings", async () => {
  for (const p of PERSONAS) {
    const db = seededDb();
    const run = await calibrateThroughServer(
      db,
      p.uid,
      persona({[p.loves]: 1, [p.dislikes]: -1}),
    );
    const v = run.vector;
    const label = `${p.uid}: ${JSON.stringify(v)}`;

    // The client buckets ≥75 high, ≥60 medium, ≤35 dislike.
    assert.ok(v[p.loves] >= 60, `loved ${p.loves} below the medium bucket — ${label}`);
    assert.ok(v[p.dislikes] <= 35, `disliked ${p.dislikes} not visible — ${label}`);
    assert.equal(strongest(v), p.loves, `headline trait is not the loved style — ${label}`);
    assert.equal(weakest(v), p.dislikes, label);

    // Exactly 15 counted ratings, one per position, no content twice.
    assert.deepEqual(run.progress, Array.from({length: CALIBRATION_TOTAL}, (_, i) => i + 1));
    assert.equal(run.summary.interactionCount, CALIBRATION_TOTAL);
    assert.equal(run.calibration.complete, true);
    const ids = run.picks.map((pick) => pick.content.contentId);
    assert.equal(new Set(ids).size, CALIBRATION_TOTAL, "duplicate content in calibration");
    assert.equal(run.calibration.degradedCount, 0);
  }

  // Most personas are clear enough for the "high" bucket outright.
  const db = seededDb();
  const sarcasm = await calibrateThroughServer(
    db,
    "persona_high",
    persona({sarcasm: 1, silly: -1}),
  );
  assert.ok(sarcasm.vector.sarcasm >= 75, JSON.stringify(sarcasm.vector));
});

test("a uniformly neutral user stays at the midpoint", async () => {
  const run = await calibrateThroughServer(seededDb(), "persona_neutral", () => "neutral");
  for (const dim of HUMOR_CATEGORIES) {
    assert.ok(Math.abs(run.vector[dim] - 50) < 1e-9, `${dim} = ${run.vector[dim]}`);
  }
  assert.equal(run.calibration.complete, true);
});

test("random ratings stay bounded instead of producing extreme profiles", async () => {
  const ratings = ["very_funny", "funny", "neutral", "not_funny", "not_at_all"];
  for (const seed of [1, 2, 3, 4, 5, 6, 7, 8]) {
    const random = lcg(seed);
    const run = await calibrateThroughServer(
      seededDb(),
      `noise_${seed}`,
      () => ratings[Math.floor(random() * ratings.length)],
    );
    const values = HUMOR_CATEGORIES.map((dim) => run.vector[dim]);
    for (const value of values) {
      assert.ok(Number.isFinite(value) && value > 10 && value < 90, `seed ${seed}: ${value}`);
    }
    const meanDeviation =
      values.reduce((sum, value) => sum + Math.abs(value - 50), 0) / values.length;
    assert.ok(meanDeviation < 20, `seed ${seed}: mean deviation ${meanDeviation}`);
  }

  // A user flip-flopping on the same style converges, it does not oscillate.
  const {applyFeedbackToProfile: apply} = require("../lib/humor/profile.js");
  let profile = defaultUserHumorProfile();
  for (let i = 0; i < 60; i += 1) {
    profile = apply({
      profile,
      contentVector: {sarcasm: 1},
      rating: i % 2 === 0 ? "very_funny" : "not_at_all",
    });
  }
  assert.ok(Math.abs(profile.vector.sarcasm - 50) < 10, String(profile.vector.sarcasm));
});

test("learning continues after calibration, with smaller steps", async () => {
  const db = seededDb();
  const uid = "persona_lifetime";
  const run = await calibrateThroughServer(db, uid, persona({sarcasm: 1, silly: -1}));
  const rated = await interactedIds(db, uid);
  const next = INTERNAL_HUMOR_SEED.find(
    (item) => !rated.has(item.contentId) && (item.humorVector.silly ?? 0) >= 0.8,
  );
  assert.ok(next, "seed needs an unrated silly item");
  const before = run.vector.silly;
  const result = await submitHumorFeedbackTx({
    db,
    uid,
    contentId: next.contentId,
    rating: "very_funny",
  });
  assert.equal(result.interactionCount, CALIBRATION_TOTAL + 1);
  assert.equal(result.calibration.completedCount, CALIBRATION_TOTAL, "milestone frozen");
  const after = db._store.get(`users/${uid}/humor/summary`).vector.silly;
  const mass = next.humorVector.silly;
  const youngStep = YOUNG_LEARNING_RATE * mass * (100 - before);
  assert.ok(after > before, "interaction 16 must still move the profile");
  assert.ok(after - before < youngStep, "…but by less than a calibration-stage step");
  assert.ok(
    Math.abs(after - before - learningRate(CALIBRATION_TOTAL + 1) * mass * (100 - before)) <
      1e-9,
  );
});

test("a user with earlier Humor Lab ratings still gets a visible profile from calibration", async () => {
  // Rated before calibration existed: a lifetime count, no calibration
  // document — so the full 15-item calibration still runs for them, and it
  // must learn at the calibration step, not the decayed mature one.
  const PRIOR = 40;
  for (const p of PERSONAS) {
    const db = seededDb();
    db._store.set(`users/${p.uid}/humor/summary`, {
      ...defaultUserHumorProfile(),
      interactionCount: PRIOR,
    });
    const run = await calibrateThroughServer(
      db,
      p.uid,
      persona({[p.loves]: 1, [p.dislikes]: -1}),
    );
    const v = run.vector;
    const label = `${p.uid}: ${JSON.stringify(v)}`;
    assert.ok(v[p.loves] >= 60, `loved ${p.loves} below the medium bucket — ${label}`);
    assert.ok(v[p.dislikes] <= 35, `disliked ${p.dislikes} not visible — ${label}`);
    assert.equal(strongest(v), p.loves, label);
    assert.equal(run.summary.interactionCount, PRIOR + CALIBRATION_TOTAL);
    assert.equal(run.calibration.complete, true);

    // Once calibration is done, the lifetime count decides the step again.
    const rated = await interactedIds(db, p.uid);
    const next = INTERNAL_HUMOR_SEED.find(
      (item) => !rated.has(item.contentId) && (item.humorVector[p.loves] ?? 0) >= 0.8,
    );
    assert.ok(next, `seed needs an unrated ${p.loves} item`);
    const before = v[p.loves];
    await submitHumorFeedbackTx({db, uid: p.uid, contentId: next.contentId, rating: "very_funny"});
    const after = db._store.get(`users/${p.uid}/humor/summary`).vector[p.loves];
    const step = learningRate(PRIOR + CALIBRATION_TOTAL + 1);
    assert.ok(step < YOUNG_LEARNING_RATE);
    assert.ok(
      Math.abs(after - before - step * next.humorVector[p.loves] * (100 - before)) < 1e-9,
      `${p.uid}: ${before} → ${after}`,
    );
  }
});

// --------------------------------------------------------------------------
// Feedback semantics: skip, markers, re-rate, same rating, saved, gestures
// --------------------------------------------------------------------------

const ANCHOR_ID = anchorIdOf("anchor_wit", 0);
const OTHER_ID = anchorIdOf("anchor_wit", 1);

test("a skip writes a marker and changes nothing else", async () => {
  const db = seededDb();
  const uid = "user_skip";
  const statsBefore = JSON.stringify(db._store.get(`humorContent/${ANCHOR_ID}`).stats);

  const result = await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, skipped: true});
  assert.equal(result.ok, true);
  assert.equal(result.interactionCount, 0);
  assert.equal(result.calibration.completedCount, 0);
  assert.deepEqual(Object.keys(result).sort(), [
    "calibration",
    "confidence",
    "interactionCount",
    "ok",
    "profileBuilding",
  ]);

  const marker = db._store.get(`users/${uid}/humorInteractions/${ANCHOR_ID}`);
  assert.deepEqual(Object.keys(marker).sort(), [
    "contentId",
    "createdAt",
    "rating",
    "skipReason",
    "skipped",
    "updatedAt",
  ]);
  assert.equal(marker.skipped, true);
  assert.equal(marker.skipReason, "user", "a skip without a reason is a user skip");
  assert.equal(marker.rating, null);
  assert.equal(db._store.has(`users/${uid}/humor/summary`), false, "profile untouched");
  assert.equal(db._store.has(`users/${uid}/humor/calibration`), false, "progress untouched");
  assert.equal(
    JSON.stringify(db._store.get(`humorContent/${ANCHOR_ID}`).stats),
    statsBefore,
    "content stats untouched",
  );
});

test("a skip of already-rated content is a no-op", async () => {
  const db = seededDb();
  const uid = "user_skip_rated";
  await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny"});
  const before = JSON.stringify(db._store.get(`users/${uid}/humorInteractions/${ANCHOR_ID}`));
  const writes = db._writes.length;
  const result = await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, skipped: true});
  assert.equal(db._writes.length, writes, "nothing may be written");
  assert.equal(
    JSON.stringify(db._store.get(`users/${uid}/humorInteractions/${ANCHOR_ID}`)),
    before,
  );
  assert.equal(result.interactionCount, 1);
  assert.equal(result.calibration.completedCount, 1);
});

test("a rating after a skip or report marker counts as the first rating", async () => {
  for (const marker of [
    {contentId: ANCHOR_ID, skipped: true, rating: null},
    {contentId: ANCHOR_ID, reported: true, skipped: true},
  ]) {
    const db = seededDb();
    const uid = "user_marker";
    db._store.set(`users/${uid}/humorInteractions/${ANCHOR_ID}`, {
      ...marker,
      createdAt: "<sentinel>",
    });
    const result = await submitHumorFeedbackTx({
      db,
      uid,
      contentId: ANCHOR_ID,
      rating: "very_funny",
    });
    assert.equal(result.interactionCount, 1);
    assert.equal(result.calibration.completedCount, 1);
    const doc = db._store.get(`users/${uid}/humorInteractions/${ANCHOR_ID}`);
    assert.equal(doc.rating, "very_funny");
    assert.equal(doc.skipped, false);
    assert.ok(doc.appliedDelta.sarcasm > 0);
    if (marker.reported) {
      assert.equal(doc.reported, true, "the report flag survives the rating");
    }
    const summary = db._store.get(`users/${uid}/humor/summary`);
    assert.ok(summary.vector.sarcasm > 50, "the profile learned from it");
    assert.equal(db._store.get(`humorContent/${ANCHOR_ID}`).stats.ratingCount, 1);
  }
});

test("resubmitting the same rating is a no-op", async () => {
  const db = seededDb();
  const uid = "user_same";
  await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny"});
  const summary = JSON.stringify(db._store.get(`users/${uid}/humor/summary`));
  const writes = db._writes.length;
  const again = await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny"});
  assert.equal(db._writes.length, writes, "same rating must not write anything");
  assert.equal(JSON.stringify(db._store.get(`users/${uid}/humor/summary`)), summary);
  assert.equal(again.interactionCount, 1);
  assert.equal(again.calibration.completedCount, 1);
});

test("changing a rating replaces its contribution end to end", async () => {
  const db = seededDb();
  await submitHumorFeedbackTx({db, uid: "u_changed", contentId: OTHER_ID, rating: "funny"});
  await submitHumorFeedbackTx({db, uid: "u_changed", contentId: ANCHOR_ID, rating: "very_funny"});
  const changed = await submitHumorFeedbackTx({
    db,
    uid: "u_changed",
    contentId: ANCHOR_ID,
    rating: "not_at_all",
  });
  await submitHumorFeedbackTx({db, uid: "u_single", contentId: OTHER_ID, rating: "funny"});
  await submitHumorFeedbackTx({db, uid: "u_single", contentId: ANCHOR_ID, rating: "not_at_all"});

  const a = db._store.get("users/u_changed/humor/summary");
  const b = db._store.get("users/u_single/humor/summary");
  for (const dim of HUMOR_CATEGORIES) {
    assert.ok(Math.abs(a.vector[dim] - b.vector[dim]) < 1e-9, `${dim}`);
  }
  assert.equal(changed.interactionCount, 2, "a re-rate is not a new interaction");
  assert.equal(a.interactionCount, b.interactionCount);
  assert.equal(changed.calibration.completedCount, 2, "nor a new calibration position");

  // Content stats follow the replacement: one rating, the new weight.
  const stats = db._store.get(`humorContent/${ANCHOR_ID}`).stats;
  assert.equal(stats.ratingCount, 2, "u_changed and u_single rated it once each");
  assert.equal(stats.ratingSum, -2);
  assert.equal(stats.avgRating, -1);
});

test("a late change of a calibration rating is replaced at the step it was learned with", async () => {
  const db = seededDb();
  const uid = "u_late";
  await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "very_funny"});
  const path = `users/${uid}/humorInteractions/${ANCHOR_ID}`;
  assert.equal(db._store.get(path).appliedStep, YOUNG_LEARNING_RATE);

  // The profile matures meanwhile: calibration done, a hundred ratings in.
  db._store.set(`users/${uid}/humor/calibration`, {
    version: HUMOR_CALIBRATION_VERSION,
    completedCount: CALIBRATION_TOTAL,
  });
  db._store.set(`users/${uid}/humor/summary`, {
    ...db._store.get(`users/${uid}/humor/summary`),
    interactionCount: 100,
  });
  const changed = await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny"});
  assert.equal(changed.interactionCount, 100);
  assert.equal(db._store.get(path).appliedStep, YOUNG_LEARNING_RATE);

  // Exactly as if the user had answered `funny` in the first place — not the
  // young contribution removed and a mature-step one put back.
  await submitHumorFeedbackTx({db, uid: "u_once", contentId: ANCHOR_ID, rating: "funny"});
  const late = db._store.get(`users/${uid}/humor/summary`).vector;
  const once = db._store.get("users/u_once/humor/summary").vector;
  for (const dim of HUMOR_CATEGORIES) {
    assert.ok(Math.abs(late[dim] - once[dim]) < 1e-9, `${dim}: ${late[dim]} vs ${once[dim]}`);
  }
});

test("changing a rating stored before contributions were recorded never stacks", async () => {
  const db = seededDb({
    // Aggregates written before ratingSum existed, including this user's rating.
    [ANCHOR_ID]: {stats: {viewCount: 1, ratingCount: 1, avgRating: 1}},
  });
  const uid = "u_legacy";
  const summaryPath = `users/${uid}/humor/summary`;
  const interactionPath = `users/${uid}/humorInteractions/${ANCHOR_ID}`;
  db._store.set(interactionPath, {contentId: ANCHOR_ID, rating: "very_funny", saved: false});
  db._store.set(summaryPath, {
    ...defaultUserHumorProfile(),
    vector: {...emptyHumorVector(50), sarcasm: 71.5, dry: 58},
    interactionCount: 20,
  });
  const summaryBefore = JSON.stringify(db._store.get(summaryPath));

  const result = await submitHumorFeedbackTx({
    db,
    uid,
    contentId: ANCHOR_ID,
    rating: "not_at_all",
  });
  assert.equal(result.interactionCount, 20, "not a new interaction");
  assert.equal(JSON.stringify(db._store.get(summaryPath)), summaryBefore, "profile untouched");
  const doc = db._store.get(interactionPath);
  assert.equal(doc.rating, "not_at_all", "the change itself is recorded");
  assert.equal("appliedDelta" in doc, false, "no fabricated contribution");

  const stats = db._store.get(`humorContent/${ANCHOR_ID}`).stats;
  assert.equal(stats.ratingCount, 1);
  assert.equal(stats.ratingSum, -1);
  assert.equal(stats.avgRating, -1);
});

test("content stats are exact and derive the average from the sum", async () => {
  const db = seededDb({
    // A document written before ratingSum existed.
    [ANCHOR_ID]: {stats: {viewCount: 4, ratingCount: 4, avgRating: 0.5}},
  });
  await submitHumorFeedbackTx({db, uid: "s1", contentId: ANCHOR_ID, rating: "not_at_all"});
  let stats = db._store.get(`humorContent/${ANCHOR_ID}`).stats;
  assert.equal(stats.ratingCount, 5);
  assert.equal(stats.viewCount, 5);
  assert.equal(stats.ratingSum, 1);
  assert.equal(stats.avgRating, 0.2);

  await submitHumorFeedbackTx({db, uid: "s1", contentId: ANCHOR_ID, rating: "very_funny"});
  stats = db._store.get(`humorContent/${ANCHOR_ID}`).stats;
  assert.equal(stats.ratingCount, 5, "a changed rating is not a new rating");
  assert.equal(stats.ratingSum, 3);
  assert.equal(stats.avgRating, 0.6);
});

test("content stats are plain increments outside any transaction", async () => {
  const db = seededDb();
  const runTransaction = db.runTransaction;
  let transactions = 0;
  db.runTransaction = (fn) => {
    transactions += 1;
    return runTransaction(fn);
  };
  const users = ["c1", "c2", "c3", "c4"];
  const ratings = ["very_funny", "funny", "not_funny", "not_at_all"];
  await Promise.all(
    users.map((uid, i) =>
      submitHumorFeedbackTx({db, uid, contentId: OTHER_ID, rating: ratings[i]}),
    ),
  );
  assert.equal(transactions, users.length, "one transaction per rating: the feedback itself");
  const stats = db._store.get(`humorContent/${OTHER_ID}`).stats;
  assert.equal(stats.ratingCount, 4);
  assert.equal(stats.viewCount, 4);
  assert.ok(Math.abs(stats.ratingSum - (1 + 0.6 - 0.5 - 1)) < 1e-9);

  // Content deleted between the rating and its stats write: the rating still
  // succeeds and the stats update does not resurrect the document.
  const gone = seededDb();
  const commit = gone.runTransaction;
  gone.runTransaction = async (fn) => {
    const out = await commit(fn);
    gone._store.delete(`humorContent/${OTHER_ID}`);
    return out;
  };
  const result = await submitHumorFeedbackTx({
    db: gone,
    uid: "c5",
    contentId: OTHER_ID,
    rating: "funny",
  });
  assert.equal(result.interactionCount, 1);
  assert.equal(gone._store.has(`humorContent/${OTHER_ID}`), false);
});

test("saved is stored only when explicitly sent", async () => {
  const db = seededDb();
  const uid = "user_saved";
  const path = `users/${uid}/humorInteractions/${ANCHOR_ID}`;
  await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny"});
  assert.equal("saved" in db._store.get(path), false);

  await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny", saved: true});
  assert.equal(db._store.get(path).saved, true);
  const count = db._store.get(`users/${uid}/humor/summary`).interactionCount;
  assert.equal(count, 1, "saving does not count as another interaction");

  await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "not_funny"});
  assert.equal(db._store.get(path).saved, true, "a later rating keeps the bookmark");
});

test("the callable payload is validated and normalized", () => {
  const ok = (data) => {
    const parsed = parseSubmitHumorFeedbackInput(data);
    assert.equal(parsed.ok, true, JSON.stringify(parsed));
    return parsed.value;
  };
  const field = (data) => {
    const parsed = parseSubmitHumorFeedbackInput(data);
    assert.equal(parsed.ok, false);
    return parsed.field;
  };

  assert.equal(field({contentId: ANCHOR_ID}), "rating", "rating required unless skipped");
  assert.equal(field({contentId: ANCHOR_ID, rating: "hilarious"}), "rating");
  assert.equal(field({contentId: ANCHOR_ID, skipped: true, rating: "bogus"}), "rating");
  assert.equal(field({contentId: "a/b", rating: "funny"}), "contentId");
  assert.equal(field({contentId: "", rating: "funny"}), "contentId");
  assert.equal(field({contentId: "x".repeat(129), rating: "funny"}), "contentId");
  assert.equal(field(null), "contentId");

  const skip = ok({contentId: ANCHOR_ID, skipped: true});
  assert.equal(skip.skipped, true);
  assert.equal(skip.rating, null);
  // A legacy client's skip carried a rating; the skip wins.
  assert.equal(ok({contentId: ANCHOR_ID, skipped: true, rating: "neutral"}).rating, null);

  const rated = ok({
    contentId: ` ${ANCHOR_ID} `,
    rating: "funny",
    saved: "true",
    dwellMs: 1e12,
    replayCount: -3,
    gestureHints: {swipeUp: "yes", swipeDown: true, payload: {deep: "x".repeat(1000)}},
  });
  assert.equal(rated.contentId, ANCHOR_ID);
  assert.equal("saved" in rated, false, "only an explicit boolean is carried");
  assert.equal(rated.replayCount, 0);
  assert.ok(rated.dwellMs <= 24 * 60 * 60 * 1000);
  assert.deepEqual(rated.gestureHints, {swipeUp: false, swipeDown: true});
  assert.equal(ok({contentId: ANCHOR_ID, rating: "funny", gestureHints: [1]}).gestureHints, null);
  assert.equal(ok({contentId: ANCHOR_ID, rating: "funny", saved: false}).saved, false);
});

test("skipReason (K3) is whitelisted and read only with skipped:true", () => {
  const parse = (data) => {
    const parsed = parseSubmitHumorFeedbackInput(data);
    assert.equal(parsed.ok, true, JSON.stringify(parsed));
    return parsed.value;
  };
  assert.equal(
    parse({contentId: ANCHOR_ID, skipped: true, skipReason: "media_failed"}).skipReason,
    "media_failed",
  );
  assert.equal(parse({contentId: ANCHOR_ID, skipped: true, skipReason: "user"}).skipReason, "user");
  assert.equal(parse({contentId: ANCHOR_ID, skipped: true}).skipReason, "user");
  for (const junk of ["MEDIA_FAILED", "crash", "", 7, {x: 1}, ["media_failed"], null]) {
    assert.equal(
      parse({contentId: ANCHOR_ID, skipped: true, skipReason: junk}).skipReason,
      "user",
      `unrecognised reason ${JSON.stringify(junk)} must become "user"`,
    );
  }
  // Without skipped:true the reason is ignored entirely, not an error.
  const rated = parse({contentId: ANCHOR_ID, rating: "funny", skipReason: "media_failed"});
  assert.equal("skipReason" in rated, false);
  assert.equal(rated.skipped, false);
});

test("a media_failed skip is stored on the marker and still changes nothing else", async () => {
  const db = seededDb();
  const uid = "user_media_failed";
  const statsBefore = JSON.stringify(db._store.get(`humorContent/${ANCHOR_ID}`).stats);
  const parsed = parseSubmitHumorFeedbackInput({
    contentId: ANCHOR_ID,
    skipped: true,
    skipReason: "media_failed",
  });
  const result = await submitHumorFeedbackTx({db, uid, ...parsed.value});
  assert.equal(result.interactionCount, 0);
  assert.equal(result.calibration.completedCount, 0);
  const marker = db._store.get(`users/${uid}/humorInteractions/${ANCHOR_ID}`);
  assert.equal(marker.skipped, true);
  assert.equal(marker.skipReason, "media_failed");
  assert.equal(marker.rating, null);
  assert.equal(db._store.has(`users/${uid}/humor/summary`), false, "profile untouched");
  assert.equal(db._store.has(`users/${uid}/humor/calibration`), false, "progress untouched");
  assert.equal(JSON.stringify(db._store.get(`humorContent/${ANCHOR_ID}`).stats), statsBefore);

  // A junk reason passed straight to the transaction is whitelisted there too.
  await submitHumorFeedbackTx({db, uid, contentId: OTHER_ID, skipped: true, skipReason: "<script>"});
  assert.equal(db._store.get(`users/${uid}/humorInteractions/${OTHER_ID}`).skipReason, "user");

  // A later real rating is still the item's first and counts normally.
  const rated = await submitHumorFeedbackTx({db, uid, contentId: ANCHOR_ID, rating: "funny"});
  assert.equal(rated.interactionCount, 1);
  assert.equal(rated.calibration.completedCount, 1);
});

test("gesture hints are stored as two booleans", async () => {
  const db = seededDb();
  const parsed = parseSubmitHumorFeedbackInput({
    contentId: ANCHOR_ID,
    rating: "funny",
    gestureHints: {swipeUp: true, junk: {nested: [1, 2, 3]}},
  });
  await submitHumorFeedbackTx({db, uid: "user_gesture", ...parsed.value});
  const doc = db._store.get(`users/user_gesture/humorInteractions/${ANCHOR_ID}`);
  assert.deepEqual(doc.gestureHints, {swipeUp: true, swipeDown: false});
});

test("taken-down content can be skipped but not rated", async () => {
  const db = seededDb({[ANCHOR_ID]: {active: false}});
  await assert.rejects(
    submitHumorFeedbackTx({db, uid: "user_down", contentId: ANCHOR_ID, rating: "funny"}),
    /content-unavailable/,
  );
  const skipped = await submitHumorFeedbackTx({
    db,
    uid: "user_down",
    contentId: ANCHOR_ID,
    skipped: true,
  });
  assert.equal(skipped.ok, true);
  await assert.rejects(
    submitHumorFeedbackTx({db, uid: "user_down", contentId: "missing_item", skipped: true}),
    /content-unavailable/,
  );
});

// --------------------------------------------------------------------------
// Uncurated content and calibration quality
// --------------------------------------------------------------------------

const UNCURATED = {
  contentId: "ext_giphy_abc",
  type: "video",
  language: "tr",
  category: "meme",
  humorTags: ["meme"],
  humorVector: {meme: 0.75, silly: 0.55},
  media: {},
  safetyStatus: "approved",
  safetyFlags: {},
  source: {type: "licensed_api", provider: "giphy", licenseRef: null},
  calibrationSlot: "anchor_meme",
  active: true,
  stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
};

function dbWithUncurated() {
  const db = seededDb();
  db._store.set(`humorContent/${UNCURATED.contentId}`, UNCURATED);
  return db;
}

test("uncurated content cannot take an anchor position while curated content remains", async () => {
  const db = dbWithUncurated();
  const result = await submitHumorFeedbackTx({
    db,
    uid: "user_uncurated",
    contentId: UNCURATED.contentId,
    rating: "very_funny",
  });
  assert.equal(result.interactionCount, 1, "the lifetime profile still learns");
  assert.equal(result.calibration.completedCount, 0, "but no anchor position is used");
  assert.equal(db._store.has("users/user_uncurated/humor/calibration"), false);
});

test("an exhausted curated pool degrades calibration instead of freezing it", async () => {
  const db = dbWithUncurated();
  const uid = "user_exhausted";
  // This user interacted with every curated item before calibration existed.
  for (const item of INTERNAL_HUMOR_SEED) {
    db._store.set(`users/${uid}/humorInteractions/${item.contentId}`, {
      contentId: item.contentId,
      rating: "neutral",
    });
  }
  const result = await submitHumorFeedbackTx({
    db,
    uid,
    contentId: UNCURATED.contentId,
    rating: "funny",
  });
  assert.equal(result.calibration.completedCount, 1);
  assert.equal(result.calibration.degraded, true);
  const state = db._store.get(`users/${uid}/humor/calibration`);
  assert.equal(state.degradedCount, 1);
  assert.deepEqual(state.coveredSlots, [], "uncurated content never covers a slot");
  assert.deepEqual(state.coveredDimensions, [], "nor adds measurement coverage");
});

test("uncurated content fills a later position only as a recorded degradation", async () => {
  const db = dbWithUncurated();
  const uid = "user_adaptive_uncurated";
  const anchors = ANCHOR_SLOTS.map(
    (slot) => INTERNAL_HUMOR_SEED.find((item) => item.calibration?.slot === slot.id),
  );
  let state = defaultCalibrationState();
  for (const item of anchors) {
    state = advanceCalibration({state, content: parseHumorContent(item.contentId, seedDocFrom(item))});
  }
  db._store.set(`users/${uid}/humor/calibration`, {...state});
  const coveredBefore = [...state.coveredDimensions];

  const result = await submitHumorFeedbackTx({
    db,
    uid,
    contentId: UNCURATED.contentId,
    rating: "funny",
  });
  assert.equal(result.calibration.completedCount, ANCHOR_INTERACTIONS + 1);
  assert.equal(result.calibration.degraded, true);
  const persisted = db._store.get(`users/${uid}/humor/calibration`);
  assert.equal(persisted.degradedCount, 1);
  assert.deepEqual(persisted.coveredDimensions, coveredBefore);
});
