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
  rotatingIndex,
  selectAdaptiveDimensions,
  selectExplorationDimensions,
  stableHash,
  stageForCompletedCount,
  stageForPosition,
  toCalibrationView,
} = require("../lib/humor/calibration.js");
const {selectCalibrationItems} = require("../lib/humor/calibrationFeed.js");
const {
  INTERNAL_HUMOR_SEED,
  parseCalibrationMeta,
  parseHumorContent,
  listCalibrationPool,
} = require("../lib/humor/contentRepository.js");
const {submitHumorFeedbackTx} = require("../lib/humor/feedback.js");
const {humorScoreForPair} = require("../lib/humor/compatibility.js");
const {defaultUserHumorProfile} = require("../lib/humor/profile.js");
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

/** FieldValue sentinels are opaque here; they are replaced by a marker. */
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
    return "<sentinel>";
  }
  return value;
}

function mergeInto(target, patch) {
  const out = {...target};
  for (const [key, value] of Object.entries(patch)) {
    out[key] =
      isPlainObject(value) && isPlainObject(out[key])
        ? mergeInto(out[key], value)
        : value;
  }
  return out;
}

function makeDb(initial = {}) {
  const store = new Map(Object.entries(initial).map(([k, v]) => [k, sanitize(v)]));

  const snapshotOf = (path) => ({
    id: path.split("/").pop(),
    exists: store.has(path),
    data: () => (store.has(path) ? store.get(path) : undefined),
  });

  const write = (path, data, options) => {
    const clean = sanitize(data);
    store.set(
      path,
      options && options.merge && store.has(path)
        ? mergeInto(store.get(path), clean)
        : clean,
    );
  };

  const docRef = (path) => ({
    path,
    id: path.split("/").pop(),
    get: async () => snapshotOf(path),
    set: async (data, options) => write(path, data, options),
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
    doc: docRef,
    collection: collectionRef,
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

// --------------------------------------------------------------------------
// Stage contract
// --------------------------------------------------------------------------

test("calibration is 6 anchor + 6 adaptive + 3 exploration = 15", () => {
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
  assert.equal(stageForPosition(0), "anchor");
  assert.equal(stageForPosition(5), "anchor");
  assert.equal(stageForPosition(6), "adaptive");
  assert.equal(stageForPosition(11), "adaptive");
  assert.equal(stageForPosition(12), "exploration");
  assert.equal(stageForPosition(14), "exploration");
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
    "stage",
    "totalCount",
    "version",
  ]);
  assert.equal(view.stage, "adaptive");
  assert.equal(view.totalCount, 15);
  assert.equal(view.complete, false);
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

  // Uncurated content advances the counter but never claims a slot.
  state = advanceCalibration({
    state,
    content: contentFor("c2", {meme: 0.8}, {
      eligible: false,
      slot: "anchor_meme",
      version: 0,
    }),
  });
  assert.equal(state.completedCount, 2);
  assert.deepEqual(state.coveredSlots, ["anchor_wit"]);
  assert.equal(state.degradedCount, 1);

  for (let i = 3; i <= 20; i += 1) {
    state = advanceCalibration({state, content: contentFor(`c${i}`, {silly: 0.7})});
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
// Adaptive + exploration policy
// --------------------------------------------------------------------------

function profileWith(vector, interactionCount = 6) {
  const base = defaultUserHumorProfile();
  return {
    ...base,
    vector: {...base.vector, ...vector},
    interactionCount,
    confidence: 0.4,
  };
}

test("adaptive selection differentiates a strong signal from its neighbours", () => {
  // Strong positive sarcasm response, sarcasm already measured by an anchor.
  const dims = selectAdaptiveDimensions({
    profile: profileWith({sarcasm: 88}),
    coveredDimensions: ["sarcasm"],
  });
  assert.equal(dims.length, ADAPTIVE_INTERACTIONS);
  // dry / teasing / dark are sarcasm's neighbours and must be probed first.
  assert.deepEqual(dims.slice(0, 3), ["dry", "teasing", "dark"]);
  assert.equal(new Set(dims).size, dims.length, "no repeated target dimension");

  // A strong *negative* signal is just as informative and must also be probed.
  const negative = selectAdaptiveDimensions({
    profile: profileWith({absurd: 8}),
    coveredDimensions: ["absurd"],
  });
  assert.deepEqual(negative.slice(0, 2), ["silly", "meme"]);
});

test("adaptive selection is deterministic and stays inside the dimension set", () => {
  const profile = profileWith({meme: 80, cringe: 22});
  const first = selectAdaptiveDimensions({profile, coveredDimensions: ["meme"]});
  const second = selectAdaptiveDimensions({profile, coveredDimensions: ["meme"]});
  assert.deepEqual(first, second);

  // Flat profile: no signal anywhere, still resolves to six distinct targets.
  const flat = selectAdaptiveDimensions({
    profile: defaultUserHumorProfile(),
    coveredDimensions: [],
  });
  assert.equal(flat.length, ADAPTIVE_INTERACTIONS);
  assert.equal(new Set(flat).size, ADAPTIVE_INTERACTIONS);
});

test("exploration prioritises undercovered dimensions over strong ones", () => {
  // Everything is covered except dry / dark / romantic, and those three carry
  // deliberately different amounts of evidence: dry none, dark a little,
  // romantic a lot.
  const profile = profileWith({sarcasm: 95, meme: 92, romantic: 60, dark: 51});
  const dims = selectExplorationDimensions({
    profile,
    coveredDimensions: [
      "sarcasm",
      "meme",
      "silly",
      "absurd",
      "situational",
      "cringe",
      "teasing",
      "wordplay",
    ],
  });
  assert.equal(dims.length, EXPLORATION_INTERACTIONS);
  // The user's strongest categories are already covered — exploration must not
  // simply re-test them.
  assert.equal(dims.includes("sarcasm"), false);
  assert.equal(dims.includes("meme"), false);
  // Ordered by information gain: weakest evidence first.
  assert.deepEqual(dims, ["dry", "dark", "romantic"]);
});

test("exploration falls back to weakest evidence once everything is covered", () => {
  // No uncovered dimension left: the tie-break must still be evidence-based
  // rather than re-probing the strongest category. Every dimension is given an
  // explicit value so "weakest evidence" is unambiguous.
  const profile = profileWith({
    sarcasm: 95, // 45
    absurd: 70, //  20
    silly: 65, //   15
    romantic: 52, // 2  ← weakest
    dark: 60, //    10
    meme: 90, //    40
    dry: 40, //     10
    wordplay: 35, // 15
    situational: 30, // 20
    cringe: 25, //  25
    teasing: 45, //  5  ← second weakest
  });
  const dims = selectExplorationDimensions({
    profile,
    coveredDimensions: [...require("../lib/humor/categories.js").HUMOR_CATEGORIES],
  });
  assert.equal(dims.length, EXPLORATION_INTERACTIONS);
  assert.equal(dims.includes("sarcasm"), false, "never the strongest signal");
  assert.equal(dims.includes("meme"), false);
  // romantic (2) then teasing (5) then dark (10, ahead of dry on the fixed
  // category order tie-break).
  assert.deepEqual(dims, ["romantic", "teasing", "dark"]);
});

// --------------------------------------------------------------------------
// Deterministic rotation
// --------------------------------------------------------------------------

test("rotation is deterministic per user and spreads across users", () => {
  assert.equal(stableHash("abc"), stableHash("abc"));
  assert.notEqual(stableHash("abc"), stableHash("abd"));
  assert.equal(rotatingIndex(0, "seed"), -1);

  const seedFor = (uid) => `${uid}:${HUMOR_CALIBRATION_VERSION}:anchor_wit`;
  assert.equal(rotatingIndex(2, seedFor("u1")), rotatingIndex(2, seedFor("u1")));

  const spread = new Set();
  for (let i = 0; i < 40; i += 1) {
    spread.add(rotatingIndex(2, seedFor(`user_${i}`)));
  }
  assert.equal(spread.size, 2, "both pool members are reachable across users");
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

test("pool query excludes inactive, unapproved and uncurated content", async () => {
  const db = seededDb({
    hc_tr_img_001: {active: false},
    hc_tr_vid_001: {safetyStatus: "needs_review"},
    hc_tr_img_002: {calibrationEligible: false, calibrationSlot: "anchor_wordplay"},
    hc_tr_vid_002: {calibrationVersion: 99},
  });
  const pool = await listCalibrationPool(db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });
  const ids = pool.map((item) => item.contentId);
  assert.equal(ids.includes("hc_tr_img_001"), false, "inactive excluded");
  assert.equal(ids.includes("hc_tr_vid_001"), false, "unapproved excluded");
  assert.equal(ids.includes("hc_tr_img_002"), false, "uncurated excluded");
  assert.equal(ids.includes("hc_tr_vid_002"), false, "foreign version excluded");
  assert.ok(ids.length > 0);
});

// --------------------------------------------------------------------------
// Selection
// --------------------------------------------------------------------------

async function runFullSelection(uid, db) {
  return selectCalibrationItems({
    db,
    uid,
    state: defaultCalibrationState(),
    profile: defaultUserHumorProfile(),
    languages: ["tr", "en"],
    limit: CALIBRATION_TOTAL,
  });
}

test("a full calibration run is 6/6/3 with no duplicate content", async () => {
  const {picks, unfilled, deficiencies} = await runFullSelection("user_a", seededDb());
  assert.deepEqual(deficiencies, []);
  assert.equal(unfilled, 0);
  assert.equal(picks.length, CALIBRATION_TOTAL);

  const stages = picks.map((p) => p.stage);
  assert.equal(stages.filter((s) => s === "anchor").length, ANCHOR_INTERACTIONS);
  assert.equal(stages.filter((s) => s === "adaptive").length, ADAPTIVE_INTERACTIONS);
  assert.equal(
    stages.filter((s) => s === "exploration").length,
    EXPLORATION_INTERACTIONS,
  );
  // Stages must appear in order, never interleaved.
  assert.deepEqual(stages, [
    ...Array(ANCHOR_INTERACTIONS).fill("anchor"),
    ...Array(ADAPTIVE_INTERACTIONS).fill("adaptive"),
    ...Array(EXPLORATION_INTERACTIONS).fill("exploration"),
  ]);

  const ids = picks.map((p) => p.content.contentId);
  assert.equal(new Set(ids).size, ids.length, "no duplicate content in calibration");

  // Every anchor position is filled by curated content carrying a real slot,
  // and each slot is used at most once.
  const anchorSlots = picks
    .filter((p) => p.stage === "anchor")
    .map((p) => p.content.calibration.slot);
  assert.equal(new Set(anchorSlots).size, ANCHOR_INTERACTIONS);
  for (const slot of anchorSlots) {
    assert.ok(isAnchorSlotId(slot));
  }
});

test("different users get different anchors from the same slots", async () => {
  const a = await runFullSelection("user_alpha", seededDb());
  const b = await runFullSelection("user_beta_2", seededDb());

  const anchorsOf = (result) =>
    result.picks
      .filter((p) => p.stage === "anchor")
      .map((p) => `${p.content.calibration.slot}:${p.content.contentId}`);

  const slotsA = anchorsOf(a).map((s) => s.split(":")[0]);
  const slotsB = anchorsOf(b).map((s) => s.split(":")[0]);
  assert.deepEqual(slotsA, slotsB, "the measured slots stay identical");
  assert.notDeepEqual(
    anchorsOf(a),
    anchorsOf(b),
    "but the actual content rotates between users",
  );

  // Same user, same result — this is what makes calibration resumable.
  const again = await runFullSelection("user_alpha", seededDb());
  assert.deepEqual(anchorsOf(again), anchorsOf(a));
});

test("selection resumes mid-calibration from server state alone", async () => {
  const db = seededDb();
  const full = await runFullSelection("user_resume", db);
  const firstFour = full.picks.slice(0, 4);

  let state = defaultCalibrationState();
  for (const pick of firstFour) {
    state = advanceCalibration({state, content: pick.content});
  }
  assert.equal(state.completedCount, 4);
  assert.equal(state.stage, "anchor");

  const resumed = await selectCalibrationItems({
    db,
    uid: "user_resume",
    state,
    profile: defaultUserHumorProfile(),
    languages: ["tr", "en"],
    limit: CALIBRATION_TOTAL,
  });
  assert.equal(resumed.picks.length, CALIBRATION_TOTAL - 4);
  assert.equal(resumed.picks[0].stage, "anchor");
  // Nothing already rated is offered again.
  const ratedIds = new Set(state.ratedContentIds);
  for (const pick of resumed.picks) {
    assert.equal(ratedIds.has(pick.content.contentId), false);
  }
  // The remaining anchors are exactly the slots not yet covered.
  const remainingSlots = resumed.picks
    .filter((p) => p.stage === "anchor")
    .map((p) => p.content.calibration.slot);
  assert.equal(remainingSlots.length, ANCHOR_INTERACTIONS - 4);
  for (const slot of remainingSlots) {
    assert.equal(state.coveredSlots.includes(slot), false);
  }
});

test("already-seen content is never served as a calibration item", async () => {
  const db = seededDb();
  const baseline = await runFullSelection("user_seen", db);
  const seen = new Set(baseline.picks.slice(0, 3).map((p) => p.content.contentId));

  const result = await selectCalibrationItems({
    db,
    uid: "user_seen",
    state: defaultCalibrationState(),
    profile: defaultUserHumorProfile(),
    languages: ["tr", "en"],
    limit: CALIBRATION_TOTAL,
    excludeContentIds: seen,
  });
  for (const pick of result.picks) {
    assert.equal(seen.has(pick.content.contentId), false);
  }
  // Slots whose whole pool was consumed still resolve via the alternate item.
  assert.equal(
    result.picks.filter((p) => p.stage === "anchor").length,
    ANCHOR_INTERACTIONS,
  );
});

test("an empty pool fails gracefully and reports the deficiency", async () => {
  const empty = makeDb({});
  const result = await selectCalibrationItems({
    db: empty,
    uid: "user_empty",
    state: defaultCalibrationState(),
    profile: defaultUserHumorProfile(),
    languages: ["tr"],
    limit: CALIBRATION_TOTAL,
  });
  assert.deepEqual(result.picks, []);
  assert.equal(result.unfilled, CALIBRATION_TOTAL);
  assert.ok(result.deficiencies.length > 0);
  assert.ok(result.deficiencies[0].startsWith("anchor:"));
});

test("a partial anchor pool stops at the gap instead of faking an anchor", async () => {
  // Remove every candidate for one slot.
  const db = seededDb({
    hc_tr_img_002: {calibrationSlot: null},
    hc_tr_img_009: {calibrationSlot: null},
  });
  const result = await selectCalibrationItems({
    db,
    uid: "user_partial",
    state: defaultCalibrationState(),
    profile: defaultUserHumorProfile(),
    languages: ["tr", "en"],
    limit: CALIBRATION_TOTAL,
  });
  assert.ok(result.unfilled > 0);
  assert.deepEqual(result.deficiencies, ["anchor:anchor_wordplay"]);
  // Everything served before the gap is still a genuine curated anchor.
  for (const pick of result.picks) {
    assert.equal(pick.stage, "anchor");
    assert.ok(isAnchorSlotId(pick.content.calibration.slot));
  }
});

test("language preference is honoured but never empties a slot", async () => {
  const db = seededDb();
  const turkish = await selectCalibrationItems({
    db,
    uid: "user_lang",
    state: defaultCalibrationState(),
    profile: defaultUserHumorProfile(),
    languages: ["tr"],
    limit: ANCHOR_INTERACTIONS,
  });
  assert.equal(turkish.picks.length, ANCHOR_INTERACTIONS);
  for (const pick of turkish.picks) {
    assert.equal(pick.content.language, "tr");
  }

  // A language with no curated content at all must still calibrate.
  const german = await selectCalibrationItems({
    db,
    uid: "user_lang",
    state: defaultCalibrationState(),
    profile: defaultUserHumorProfile(),
    languages: ["de"],
    limit: ANCHOR_INTERACTIONS,
  });
  assert.equal(german.picks.length, ANCHOR_INTERACTIONS);
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
  const doc = parseHumorContent("hc_tr_img_001", {
    ...seedDocFrom(INTERNAL_HUMOR_SEED.find((i) => i.contentId === "hc_tr_img_001")),
  });
  const safe = toFeedSafeContent(doc, "anchor");
  assert.equal(safe.calibrationStage, "anchor");
  assert.equal("calibrationSlot" in safe, false);
  assert.equal("humorVector" in safe, false);
  assert.equal("safetyFlags" in safe, false);
  assert.equal("safetyStatus" in safe, false);
  assert.equal(toFeedSafeContent(doc).calibrationStage, null);
});
