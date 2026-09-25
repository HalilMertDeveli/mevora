const test = require("node:test");
const assert = require("node:assert/strict");

const {buildHumorFeed} = require("../lib/humor/feed.js");
const {listHumorContentPage} = require("../lib/humor/contentRepository.js");
const {CALIBRATION_TOTAL} = require("../lib/humor/calibration.js");

/**
 * Firestore double with the ordering, cursor and getAll semantics this feed
 * depends on. The in-memory suite cannot prove index behaviour — the emulator
 * flow does that — but it can prove the pagination *algorithm*, which is where
 * the exhaustion bug lived.
 */
function makeDb(seedDocs = {}) {
  const store = new Map(Object.entries(seedDocs));

  const snapshotOf = (path) => ({
    id: path.split("/").pop(),
    exists: store.has(path),
    data: () => store.get(path),
    get: (field) => (store.get(path) ?? {})[field],
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
    const build = (state) => ({
      where: (field, op, value) => {
        assert.equal(op, "==");
        return build({...state, filters: [...state.filters, [field, value]]});
      },
      orderBy: (field, dir) =>
        build({...state, order: [...state.order, [field, dir ?? "asc"]]}),
      startAfter: (...values) => build({...state, after: values}),
      limit: (n) => build({...state, max: n}),
      select: () => build(state),
      doc: (id) => docRef(`${collectionPath}/${id}`),
      get: async () => {
        const prefix = `${collectionPath}/`;
        let rows = [];
        for (const [path, data] of store.entries()) {
          if (!path.startsWith(prefix)) continue;
          if (path.slice(prefix.length).includes("/")) continue;
          const id = path.slice(prefix.length);
          if (!state.filters.every(([f, v]) => data[f] === v)) continue;
          // orderBy excludes documents missing the ordering field, exactly
          // like Firestore — the invariant the feed relies on.
          if (state.order.some(([f]) => f !== "__name__" && data[f] === undefined)) {
            continue;
          }
          rows.push({id, data});
        }

        const keyOf = (row, field) =>
          field === "__name__" ? row.id : row.data[field]?.toMillis?.() ?? row.data[field];

        if (state.order.length > 0) {
          rows.sort((a, b) => {
            for (const [field, dir] of state.order) {
              const av = keyOf(a, field);
              const bv = keyOf(b, field);
              if (av === bv) continue;
              const cmp = av < bv ? -1 : 1;
              return dir === "desc" ? -cmp : cmp;
            }
            return 0;
          });
        } else {
          rows.sort((a, b) => (a.id < b.id ? -1 : 1));
        }

        if (state.after) {
          const cursorKeys = state.after.map((v) => v?.toMillis?.() ?? v?.id ?? v);
          const index = rows.findIndex((row) =>
            state.order.every(
              (o, i) => String(keyOf(row, o[0])) === String(cursorKeys[i]),
            ),
          );
          rows = index >= 0 ? rows.slice(index + 1) : rows;
        }

        const limited = state.max ? rows.slice(0, state.max) : rows;
        return {
          docs: limited.map((row) => ({
            id: row.id,
            data: () => row.data,
            get: (field) => row.data[field],
          })),
          empty: limited.length === 0,
        };
      },
    });
    return build({filters: [], order: [], after: null, max: undefined});
  };

  return {
    _store: store,
    doc: docRef,
    collection: collectionRef,
    getAll: async (...refs) => refs.map((ref) => snapshotOf(ref.path)),
    runTransaction: async (fn) =>
      fn({
        get: async (ref) => snapshotOf(ref.path),
        set: (ref, data, options) =>
          store.set(
            ref.path,
            options?.merge && store.has(ref.path)
              ? {...store.get(ref.path), ...data}
              : data,
          ),
      }),
  };
}

const ts = (ms) => ({toMillis: () => ms});

/** A catalog far larger than the old 120-document window. */
function catalogOf(
  count,
  {language = "tr", createdAtBase = 1_700_000_000_000, prefix = "hc"} = {},
) {
  const docs = {};
  for (let i = 0; i < count; i += 1) {
    const id = `${prefix}_${String(i).padStart(4, "0")}`;
    docs[`humorContent/${id}`] = {
      contentId: id,
      type: "meme",
      language,
      category: "meme",
      humorTags: [],
      humorVector: {meme: 0.8},
      media: {downloadUrl: `https://example.test/${id}.png`},
      safetyStatus: "approved",
      safetyFlags: {},
      source: {type: "internal", provider: "mevora-internal", licenseRef: null},
      active: true,
      createdAt: ts(createdAtBase + i * 1000),
      stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    };
  }
  return docs;
}

/** Mark calibration complete so the generic feed path is the one under test. */
function withCompletedCalibration(docs, uid) {
  return {
    ...docs,
    [`users/${uid}/humor/calibration`]: {
      version: 1,
      completedCount: CALIBRATION_TOTAL,
      stage: "complete",
      complete: true,
      ratedContentIds: [],
      coveredSlots: [],
      coveredDimensions: [],
      degradedCount: 0,
    },
  };
}

function markRated(db, uid, contentIds) {
  for (const id of contentIds) {
    db._store.set(`users/${uid}/humorInteractions/${id}`, {
      contentId: id,
      rating: "funny",
    });
  }
}

async function feed(db, uid, cursor = null, limit = 12) {
  return buildHumorFeed({db, uid, languages: ["tr"], limit, cursor});
}

// --------------------------------------------------------------------------

test("pagination walks past the old 120-document window", async () => {
  const uid = "u_deep";
  const db = makeDb(withCompletedCalibration(catalogOf(400), uid));

  const served = new Set();
  let cursor = null;
  let pages = 0;
  while (pages < 60) {
    const result = await feed(db, uid, cursor);
    if (result.items.length === 0) break;
    for (const item of result.items) {
      assert.equal(served.has(item.contentId), false, `repeat: ${item.contentId}`);
      served.add(item.contentId);
    }
    cursor = result.nextCursor;
    pages += 1;
    if (!cursor) break;
  }

  // The regression: the old implementation could never serve more than the
  // first 120 documents, whatever the catalog size.
  assert.ok(
    served.size > 120,
    `pagination stalled at ${served.size} items — the 120 window is back`,
  );
  assert.ok(served.size >= 350, `only reached ${served.size} of 400`);
});

test("a fully rated catalog reports exhaustion instead of looping", async () => {
  const uid = "u_exhaust";
  const db = makeDb(withCompletedCalibration(catalogOf(40), uid));
  markRated(
    db,
    uid,
    Object.keys(db._store)
      .filter(() => false)
      .concat(
        [...db._store.keys()]
          .filter((k) => k.startsWith("humorContent/"))
          .map((k) => k.split("/")[1]),
      ),
  );

  const result = await feed(db, uid);
  assert.deepEqual(result.items, []);
  assert.equal(result.nextCursor, null, "must not invite another page");
  assert.equal(result.catalogExhausted, true);
  assert.equal(result.catalogEmpty, false, "the catalog has content, it is all seen");
});

test("an empty catalog is distinguishable from an exhausted one", async () => {
  const uid = "u_empty";
  const db = makeDb(withCompletedCalibration({}, uid));

  const result = await feed(db, uid);
  assert.deepEqual(result.items, []);
  assert.equal(result.nextCursor, null);
  assert.equal(result.catalogEmpty, true);
});

test("seen items no longer consume page slots", async () => {
  const uid = "u_slots";
  const db = makeDb(withCompletedCalibration(catalogOf(80), uid));
  // Rate most of the newest content: the old code ranked these in, capped at
  // `limit`, then filtered them out — returning a nearly empty page while
  // plenty of unseen content existed.
  const ids = [...Array(60)].map((_, i) => `hc_${String(79 - i).padStart(4, "0")}`);
  markRated(db, uid, ids);

  const result = await feed(db, uid, null, 12);
  assert.equal(result.items.length, 12, "page came back short despite unseen content");
  for (const item of result.items) {
    assert.equal(ids.includes(item.contentId), false);
  }
});

test("an oversized seen set still never yields a repeat", async () => {
  // Beyond the bounded seen prefetch, correctness falls to the exact check on
  // the items actually being served.
  const uid = "u_heavy";
  const db = makeDb(withCompletedCalibration(catalogOf(60), uid));
  const rated = [...Array(55)].map((_, i) => `hc_${String(59 - i).padStart(4, "0")}`);
  markRated(db, uid, rated);

  const result = await feed(db, uid, null, 12);
  for (const item of result.items) {
    assert.equal(
      rated.includes(item.contentId),
      false,
      `served already-rated ${item.contentId}`,
    );
  }
  assert.equal(result.items.length, 5, "the five genuinely unseen items");
});

test("content lacking createdAt is invisible, so upserts must stamp it", async () => {
  // Locks the ordering-key invariant the pagination depends on.
  const uid = "u_nocreated";
  const docs = withCompletedCalibration(catalogOf(5), uid);
  delete docs["humorContent/hc_0002"].createdAt;
  const db = makeDb(docs);

  const page = await listHumorContentPage(db, {languages: ["tr"], pageSize: 60});
  const ids = page.entries.map((e) => e.content.contentId);
  assert.equal(ids.includes("hc_0002"), false);
  assert.equal(ids.length, 4);
  // Every entry must carry its own position so the feed cursor can stop on a
  // served item rather than a scanned one.
  for (const entry of page.entries) {
    assert.equal(typeof entry.position.createdAtMs, "number");
    assert.equal(entry.position.contentId, entry.content.contentId);
  }

  const {upsertHumorContentDoc} = require("../lib/humor/contentRepository.js");
  const fresh = makeDb({});
  await upsertHumorContentDoc(fresh, {
    contentId: "hc_new",
    type: "meme",
    language: "tr",
    category: "meme",
    humorVector: {meme: 0.9},
    safetyStatus: "approved",
    active: true,
  });
  const written = fresh._store.get("humorContent/hc_new");
  assert.ok(
    written.createdAt !== undefined,
    "upsert must stamp createdAt or the item can never be served",
  );
});

test("inactive and unapproved content stays out of every page", async () => {
  const uid = "u_safety";
  const docs = withCompletedCalibration(catalogOf(30), uid);
  docs["humorContent/hc_0029"].active = false;
  docs["humorContent/hc_0028"].safetyStatus = "rejected";
  docs["humorContent/hc_0027"].safetyStatus = "needs_review";
  const db = makeDb(docs);

  let cursor = null;
  const served = [];
  for (let i = 0; i < 10; i += 1) {
    const result = await feed(db, uid, cursor);
    served.push(...result.items.map((x) => x.contentId));
    cursor = result.nextCursor;
    if (!cursor || result.items.length === 0) break;
  }
  for (const blocked of ["hc_0029", "hc_0028", "hc_0027"]) {
    assert.equal(served.includes(blocked), false, `served blocked ${blocked}`);
  }
  assert.ok(served.length > 0);
});

test("language preference is respected across pages", async () => {
  const uid = "u_lang";
  const docs = withCompletedCalibration(catalogOf(40, {language: "tr"}), uid);
  // Newer English content, so it would dominate a naive newest-first scan.
  Object.assign(
    docs,
    catalogOf(40, {
      language: "en",
      prefix: "en",
      createdAtBase: 1_800_000_000_000,
    }),
  );
  const db = makeDb(docs);

  const result = await buildHumorFeed({db, uid, languages: ["tr"], limit: 12});
  for (const item of result.items) {
    assert.equal(item.language, "tr");
  }
  assert.equal(result.items.length, 12);
});

test("a forged or corrupt cursor degrades to the start, never throws", async () => {
  const uid = "u_cursor";
  const db = makeDb(withCompletedCalibration(catalogOf(40), uid));

  for (const bad of ["", "!!!not-base64!!!", Buffer.from("{}").toString("base64url")]) {
    const result = await feed(db, uid, bad);
    assert.ok(result.items.length > 0, `cursor ${JSON.stringify(bad)} broke the feed`);
  }
});

test("calibration owns the page and carries no catalog cursor", async () => {
  // Phase 1 must not couple calibration to the paginated path.
  const {ANCHOR_SLOTS, HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");
  const uid = "u_calibrating";
  const docs = catalogOf(40);
  // Curate two candidates per anchor slot out of the catalog.
  ANCHOR_SLOTS.forEach((slot, index) => {
    for (const offset of [0, 1]) {
      const id = `hc_${String(index * 2 + offset).padStart(4, "0")}`;
      Object.assign(docs[`humorContent/${id}`], {
        calibrationEligible: true,
        calibrationSlot: slot.id,
        calibrationVersion: HUMOR_CALIBRATION_VERSION,
        humorVector: {[slot.primary]: 0.9},
        category: slot.primary,
      });
    }
  });
  const db = makeDb(docs);

  const result = await feed(db, uid);
  assert.equal(result.calibration.complete, false);
  assert.equal(result.items.length > 0, true);
  assert.equal(result.items[0].calibrationStage, "anchor");
  assert.equal(result.nextCursor, null, "calibration pages carry no catalog cursor");
  assert.equal(result.catalogExhausted, false);
});

test("calibration falls back to the generic feed when nothing is curated", async () => {
  // Graceful degradation, not a stall: an uncurated catalog must still serve
  // content rather than leaving the user with a blank Humor Lab.
  const uid = "u_nopool";
  const db = makeDb(catalogOf(40));
  const result = await feed(db, uid);
  assert.equal(result.calibration.complete, false);
  assert.equal(result.calibration.insufficientPool, true, "the gap must be reported");
  assert.ok(result.items.length > 0, "fallback served nothing");
  for (const item of result.items) {
    assert.equal(
      item.calibrationStage,
      null,
      "fallback content must not be labelled a calibration item",
    );
  }
});
