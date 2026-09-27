const test = require("node:test");
const assert = require("node:assert/strict");

const {buildHumorFeed} = require("../lib/humor/feed.js");
const {listHumorContentPage} = require("../lib/humor/contentRepository.js");
const {CALIBRATION_TOTAL} = require("../lib/humor/calibration.js");

const isTimestampLike = (value) =>
  value !== null &&
  typeof value === "object" &&
  typeof value.seconds === "number" &&
  typeof value.nanoseconds === "number";

/** Firestore value order for the handful of types the feed orders by. */
function compareValues(a, b) {
  if (isTimestampLike(a) && isTimestampLike(b)) {
    return Math.sign(a.seconds - b.seconds || a.nanoseconds - b.nanoseconds);
  }
  const av = a !== null && typeof a === "object" && "id" in a ? a.id : a;
  const bv = b !== null && typeof b === "object" && "id" in b ? b.id : b;
  return av === bv ? 0 : av < bv ? -1 : 1;
}

/**
 * Firestore double with the ordering, cursor and getAll semantics this feed
 * depends on. Cursors compare at full timestamp precision, exactly like
 * Firestore, so a position truncated to milliseconds really does land in the
 * wrong place here. The in-memory suite cannot prove index behaviour — the
 * emulator flow does that — but it can prove the pagination *algorithm*.
 *
 * `_stats` counts billed reads (a query bills at least one), getAll refs and
 * writes, so the tests can pin how much a call costs.
 */
function makeDb(seedDocs = {}) {
  const store = new Map(Object.entries(seedDocs));
  const stats = {reads: 0, writes: [], queried: []};

  const snapshotOf = (path) => ({
    id: path.split("/").pop(),
    exists: store.has(path),
    data: () => store.get(path),
    get: (field) => (store.get(path) ?? {})[field],
  });

  const write = (path, data, options) => {
    stats.writes.push(path);
    if (options?.mergeFields) {
      const next = {...(store.get(path) ?? {})};
      for (const field of options.mergeFields) {
        next[field] = data[field];
      }
      store.set(path, next);
      return;
    }
    store.set(
      path,
      options?.merge && store.has(path) ? {...store.get(path), ...data} : data,
    );
  };

  const docRef = (path) => ({
    path,
    id: path.split("/").pop(),
    get: async () => {
      stats.reads += 1;
      return snapshotOf(path);
    },
    set: async (data, options) => write(path, data, options),
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
      endBefore: (...values) => build({...state, before: values}),
      limit: (n) => build({...state, max: n}),
      select: () => build(state),
      doc: (id) => docRef(`${collectionPath}/${id}`),
      get: async () => {
        stats.queried.push(collectionPath);
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

        const keyOf = (row, field) => (field === "__name__" ? row.id : row.data[field]);
        const compareToValues = (row, values) => {
          for (let i = 0; i < state.order.length; i += 1) {
            const [field, dir] = state.order[i];
            const cmp = compareValues(keyOf(row, field), values[i]);
            if (cmp !== 0) return dir === "desc" ? -cmp : cmp;
          }
          return 0;
        };

        if (state.order.length > 0) {
          rows.sort((a, b) => {
            for (const [field, dir] of state.order) {
              const cmp = compareValues(keyOf(a, field), keyOf(b, field));
              if (cmp !== 0) return dir === "desc" ? -cmp : cmp;
            }
            return 0;
          });
        } else {
          rows.sort((a, b) => (a.id < b.id ? -1 : 1));
        }

        if (state.after) {
          rows = rows.filter((row) => compareToValues(row, state.after) > 0);
        }
        if (state.before) {
          rows = rows.filter((row) => compareToValues(row, state.before) < 0);
        }

        const limited = state.max ? rows.slice(0, state.max) : rows;
        stats.reads += Math.max(1, limited.length);
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
    return build({filters: [], order: [], after: null, before: null, max: undefined});
  };

  return {
    _store: store,
    _stats: stats,
    doc: docRef,
    collection: collectionRef,
    getAll: async (...refs) => {
      stats.reads += refs.length;
      return refs.map((ref) => snapshotOf(ref.path));
    },
    runTransaction: async (fn) =>
      fn({
        get: async (ref) => snapshotOf(ref.path),
        set: (ref, data, options) => write(ref.path, data, options),
      }),
  };
}

/** A timestamp at `ms`, optionally with sub-millisecond nanoseconds on top. */
const ts = (ms, extraNanos = 0) => {
  const seconds = Math.floor(ms / 1000);
  return {
    seconds,
    nanoseconds: (ms - seconds * 1000) * 1_000_000 + extraNanos,
    toMillis: () => ms,
  };
};

const BASE_MS = 1_700_000_000_000;

function contentDoc(id, {language = "tr", createdAt}) {
  return {
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
    createdAt,
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
  };
}

/** A catalog far larger than the old 120-document window. */
function catalogOf(count, {language = "tr", createdAtBase = BASE_MS, prefix = "hc"} = {}) {
  const docs = {};
  for (let i = 0; i < count; i += 1) {
    const id = `${prefix}_${String(i).padStart(4, "0")}`;
    docs[`humorContent/${id}`] = contentDoc(id, {
      language,
      createdAt: ts(createdAtBase + i * 1000),
    });
  }
  return docs;
}

const idsOf = (docs) =>
  Object.keys(docs)
    .filter((key) => key.startsWith("humorContent/"))
    .map((key) => key.split("/")[1]);

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

function markRated(db, uid, contentIds, marker = {rating: "funny"}) {
  for (const id of contentIds) {
    db._store.set(`users/${uid}/humorInteractions/${id}`, {contentId: id, ...marker});
  }
}

const cursorFor = (body) => Buffer.from(JSON.stringify(body), "utf8").toString("base64url");

async function feed(db, uid, cursor = null, limit = 12, extra = {}) {
  return buildHumorFeed({db, uid, languages: ["tr"], limit, cursor, ...extra});
}

/** Follow cursors like a client that never rates. */
async function walkByCursor(db, uid, {limit = 12, maxCalls = 200, languages = ["tr"]} = {}) {
  const served = [];
  let cursor = null;
  let last = null;
  for (let calls = 0; calls < maxCalls; calls += 1) {
    last = await buildHumorFeed({db, uid, languages, limit, cursor});
    served.push(...last.items.map((item) => item.contentId));
    cursor = last.nextCursor;
    if (!cursor) break;
  }
  return {served, last};
}

/** Cold calls only, rating every served item, until "caught up". */
async function rateToExhaustion(db, uid, {limit = 15, maxCalls = 120, now} = {}) {
  const served = [];
  for (let calls = 1; calls <= maxCalls; calls += 1) {
    const result = await buildHumorFeed({db, uid, languages: ["tr"], limit, now});
    served.push(...result.items.map((item) => item.contentId));
    markRated(db, uid, result.items.map((item) => item.contentId));
    if (result.catalogExhausted) {
      assert.deepEqual(result.items, [], "exhausted page carried items");
      assert.equal(result.nextCursor, null);
      return {served, calls};
    }
  }
  throw new Error(`never reached exhaustion after ${served.length} served`);
}

// --------------------------------------------------------------------------

test("pagination walks the whole catalog: exactly 400 of 400, no repeats", async () => {
  const uid = "u_deep";
  const db = makeDb(withCompletedCalibration(catalogOf(400), uid));

  const {served, last} = await walkByCursor(db, uid);
  assert.equal(new Set(served).size, served.length, "the walk repeated content");
  // The regression: the old implementation could never serve more than the
  // first 120 documents, and a later one skipped some of the rest.
  assert.equal(served.length, 400, `reached ${served.length} of 400`);
  assert.equal(last.nextCursor, null, "the end of the walk must not invite another page");
});

test("a fully rated catalog reports exhaustion instead of looping", async () => {
  const uid = "u_exhaust";
  const docs = withCompletedCalibration(catalogOf(40), uid);
  const db = makeDb(docs);
  markRated(db, uid, idsOf(docs));

  const result = await feed(db, uid);
  assert.deepEqual(result.items, []);
  assert.equal(result.nextCursor, null, "must not invite another page");
  assert.equal(result.catalogExhausted, true);
  assert.equal(result.catalogEmpty, false, "the catalog has content, it is all seen");
});

test("a fully rated catalog larger than one call's scan budget stays exhausted", async () => {
  // 300 > MAX_SCAN_PAGES × SCAN_PAGE_SIZE (240): no single call can see it all.
  const uid = "u_big_exhaust";
  const docs = withCompletedCalibration(catalogOf(300), uid);
  const db = makeDb(docs);
  markRated(db, uid, idsOf(docs));

  // Nothing is known yet: the first call must not claim exhaustion from a
  // partial walk, and must hand back a cursor so the walk can continue.
  const first = await feed(db, uid);
  assert.deepEqual(first.items, []);
  assert.equal(first.catalogExhausted, false, "claimed exhaustion from a partial walk");
  assert.ok(first.nextCursor, "a partial walk must invite the next page");

  // The sweep began at the top, so once it reaches the end it is proof.
  const second = await feed(db, uid);
  assert.equal(second.catalogExhausted, true);
  assert.equal(second.nextCursor, null);

  // The old code reset to the top here and alternated empty / caught-up.
  for (const label of ["third", "fourth"]) {
    const writesBefore = db._stats.writes.length;
    const readsBefore = db._stats.reads;
    const again = await feed(db, uid);
    assert.equal(again.catalogExhausted, true, `${label} cold call lost the caught-up state`);
    assert.deepEqual(again.items, []);
    assert.equal(again.nextCursor, null);
    assert.equal(db._stats.writes.length, writesBefore, "an unchanged position was rewritten");
    assert.ok(db._stats.reads - readsBefore <= 4, "caught-up calls must stay cheap");
  }
});

test("rating through the feed reaches a stable caught-up state", async () => {
  const uid = "u_rate_through";
  const db = makeDb(withCompletedCalibration(catalogOf(300), uid));

  const {served} = await rateToExhaustion(db, uid);
  assert.equal(new Set(served).size, served.length, "an item was served twice");
  assert.equal(served.length, 300);

  for (let i = 0; i < 2; i += 1) {
    const again = await feed(db, uid);
    assert.equal(again.catalogExhausted, true, `cold call ${i + 1} after exhaustion`);
    assert.deepEqual(again.items, []);
  }
});

test("new content above a caught-up user is served, then caught up again", async () => {
  const uid = "u_new_content";
  const docs = withCompletedCalibration(catalogOf(80), uid);
  const db = makeDb(docs);
  markRated(db, uid, idsOf(docs));
  assert.equal((await feed(db, uid)).catalogExhausted, true);

  db._store.set(
    "humorContent/hc_fresh",
    contentDoc("hc_fresh", {createdAt: ts(BASE_MS + 10_000_000)}),
  );
  const fresh = await feed(db, uid);
  assert.deepEqual(fresh.items.map((item) => item.contentId), ["hc_fresh"]);
  assert.equal(fresh.catalogExhausted, false);

  markRated(db, uid, ["hc_fresh"]);
  const after = await feed(db, uid);
  assert.equal(after.catalogExhausted, true);
});

test("a stale caught-up state re-walks the catalog and finds late-approved content", async () => {
  const uid = "u_stale_floor";
  const docs = withCompletedCalibration(catalogOf(300), uid);
  const db = makeDb(docs);
  markRated(db, uid, idsOf(docs));
  const now = Date.now();
  await rateToExhaustion(db, uid, {now});

  // Content approved long after it was created sits below the proof.
  db._store.set(
    "humorContent/hc_late",
    contentDoc("hc_late", {createdAt: ts(BASE_MS - 60_000)}),
  );
  const fresh = await feed(db, uid, null, 12, {now: now + 60_000});
  assert.equal(fresh.catalogExhausted, true, "a fresh proof is trusted");

  const later = now + 25 * 60 * 60 * 1000;
  const served = [];
  for (let i = 0; i < 4 && served.length === 0; i += 1) {
    const result = await feed(db, uid, null, 12, {now: later});
    served.push(...result.items.map((item) => item.contentId));
    if (result.items.length === 0) {
      // Re-walking must not flap to an ambiguous empty state in between.
      assert.equal(result.catalogExhausted, true, "the re-walk dropped the caught-up state");
      assert.equal(result.nextCursor, null);
    }
  }
  assert.deepEqual(served, ["hc_late"]);
});

test("a walk resumed from the middle never claims exhaustion", async () => {
  const uid = "u_partial";
  const docs = withCompletedCalibration(catalogOf(100), uid);
  // The 60 oldest are rated; the 40 newest are not.
  const rated = [...Array(60)].map((_, i) => `hc_${String(i).padStart(4, "0")}`);
  const pivot = docs["humorContent/hc_0060"].createdAt;
  const db = makeDb(docs);
  markRated(db, uid, rated);

  // An explicit cursor above the rated tail: this pass ends at the bottom, but
  // the unseen top was never swept, so it is not "caught up".
  const viaCursor = await feed(
    db,
    uid,
    cursorFor({s: pivot.seconds, n: pivot.nanoseconds, id: "hc_0060"}),
  );
  assert.deepEqual(viaCursor.items, []);
  assert.equal(viaCursor.nextCursor, null, "a cursor walk is one pass");
  assert.equal(viaCursor.catalogExhausted, false, "partial walk reported exhaustion");
  assert.equal(viaCursor.catalogEmpty, false);

  // The next cold start begins the next pass at the top.
  const next = await feed(db, uid);
  assert.equal(next.items.length, 12);
  for (const item of next.items) {
    assert.equal(rated.includes(item.contentId), false);
  }

  // A cold start from a legacy (millisecond) stored position wraps by itself.
  const cold = makeDb(docs);
  markRated(cold, uid, rated);
  cold._store.set(`users/${uid}/humor/summary`, {
    feedPosition: {createdAtMs: pivot.toMillis(), contentId: "hc_0059"},
  });
  const resumed = await feed(cold, uid);
  assert.equal(resumed.catalogExhausted, false);
  assert.equal(resumed.items.length, 12);
});

test("a cold start re-offers items that were fetched but never rated", async () => {
  const uid = "u_resume";
  const db = makeDb(withCompletedCalibration(catalogOf(100), uid));

  // Cold load, then a prefetch by cursor, as the client does.
  const pageA = await feed(db, uid);
  const pageB = await feed(db, uid, pageA.nextCursor);
  const idsA = pageA.items.map((item) => item.contentId);
  const idsB = pageB.items.map((item) => item.contentId);
  assert.equal(new Set([...idsA, ...idsB]).size, 24);

  // The user rates all of A and a third of B, then leaves.
  markRated(db, uid, [...idsA, ...idsB.slice(0, 4)]);

  // Cold start, no cursor: the stored position alone must bring B back.
  const resumed = await feed(db, uid);
  const resumedIds = resumed.items.map((item) => item.contentId);
  for (const id of idsB.slice(4)) {
    assert.ok(resumedIds.includes(id), `fetched-but-unrated ${id} was skipped`);
  }
  for (const id of [...idsA, ...idsB.slice(0, 4)]) {
    assert.equal(resumedIds.includes(id), false, `re-served rated ${id}`);
  }
  assert.equal(resumed.items.length, 12, "the rest of the page comes from the walk");

  // A page fetched and thrown away unseen (the client prefetches just as
  // calibration completes and navigates away) comes back on the next start.
  markRated(db, uid, resumedIds);
  const discarded = await feed(db, uid, resumed.nextCursor);
  const again = await feed(db, uid);
  assert.deepEqual(
    again.items.map((item) => item.contentId).sort(),
    discarded.items.map((item) => item.contentId).sort(),
    "the discarded page was skipped",
  );
});

test("a re-offered item the user still has not rated blocks the exhaustion proof", async () => {
  const uid = "u_carried_unrated";
  const docs = withCompletedCalibration(catalogOf(300), uid);
  const db = makeDb(docs);
  // Everything is rated except one item that was served before and left.
  markRated(db, uid, idsOf(docs).filter((id) => id !== "hc_0200"));
  db._store.set(`users/${uid}/humor/summary`, {
    feedPosition: {v: 2, lang: "tr", at: null, run: null, floor: null, pending: ["hc_0200"]},
  });

  // The cold start re-offers it, and its sweep passes it on the way down.
  const cold = await feed(db, uid);
  assert.deepEqual(cold.items.map((item) => item.contentId), ["hc_0200"]);
  assert.ok(cold.nextCursor);

  // Following the cursor to the end must not count that sweep as clean.
  const followed = await feed(db, uid, cold.nextCursor);
  assert.equal(followed.catalogExhausted, false, "claimed exhaustion over an unrated item");

  const again = await feed(db, uid);
  assert.deepEqual(again.items.map((item) => item.contentId), ["hc_0200"], "item was lost");
});

test("skip and report markers keep content out of the feed", async () => {
  const uid = "u_markers";
  const db = makeDb(withCompletedCalibration(catalogOf(50), uid));
  const skipped = ["hc_0049", "hc_0030", "hc_0012"];
  const reported = ["hc_0048", "hc_0001"];
  markRated(db, uid, skipped, {skipped: true, rating: null});
  markRated(db, uid, reported, {reported: true, skipped: true});

  const {served} = await walkByCursor(db, uid);
  for (const id of [...skipped, ...reported]) {
    assert.equal(served.includes(id), false, `served marked ${id}`);
  }
  assert.equal(served.length, 45);
  assert.equal(new Set(served).size, 45);
});

test("more than 1000 interactions: only unrated items, bounded reads, no history scan", async () => {
  const uid = "u_heavy";
  const docs = withCompletedCalibration(catalogOf(1200), uid);
  const db = makeDb(docs);
  const unrated = new Set();
  const rated = [];
  idsOf(docs).forEach((id, index) => {
    if (index % 10 === 0) unrated.add(id);
    else rated.push(id);
  });
  markRated(db, uid, rated);
  assert.ok(rated.length > 1000);

  const served = [];
  let cursor = null;
  for (let calls = 0; calls < 60; calls += 1) {
    const readsBefore = db._stats.reads;
    const result = await feed(db, uid, cursor);
    // Summary + calibration + ≤ 4 scan pages + ≤ one lookup per scanned doc.
    assert.ok(db._stats.reads - readsBefore <= 2 + 4 * 60 * 2, "a feed call read too much");
    served.push(...result.items.map((item) => item.contentId));
    cursor = result.nextCursor;
    if (!cursor) break;
  }
  for (const id of served) {
    assert.ok(unrated.has(id), `served already-rated ${id}`);
  }
  assert.equal(new Set(served).size, served.length);
  assert.equal(served.length, unrated.size, "every unrated item is reachable");
  assert.equal(
    db._stats.queried.some((path) => path.includes("humorInteractions")),
    false,
    "the feed must not scan the interaction history",
  );
});

test("rated items beyond one scan page never leak into a page", async () => {
  const uid = "u_leak";
  const db = makeDb(withCompletedCalibration(catalogOf(60), uid));
  const rated = [...Array(55)].map((_, i) => `hc_${String(59 - i).padStart(4, "0")}`);
  markRated(db, uid, rated);

  const result = await feed(db, uid, null, 12);
  for (const item of result.items) {
    assert.equal(rated.includes(item.contentId), false, `served already-rated ${item.contentId}`);
  }
  assert.equal(result.items.length, 5, "the five genuinely unseen items");
});

test("an empty catalog is distinguishable from an exhausted one", async () => {
  const uid = "u_empty";
  const db = makeDb(withCompletedCalibration({}, uid));

  const result = await feed(db, uid);
  assert.deepEqual(result.items, []);
  assert.equal(result.nextCursor, null);
  assert.equal(result.catalogEmpty, true);
  assert.equal(result.catalogExhausted, false);
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

test("documents sharing a sub-millisecond createdAt are never skipped", async () => {
  // One batch commit stamps every document with the same microsecond
  // timestamp; positions truncated to millis skipped the rest of such a group
  // at every page boundary.
  const uid = "u_precision";
  const docs = {};
  for (let i = 0; i < 30; i += 1) {
    const id = `hp_${String(i).padStart(2, "0")}`;
    // Ten distinct sub-millisecond timestamps, three documents on each.
    docs[`humorContent/${id}`] = contentDoc(id, {
      createdAt: ts(BASE_MS, 250_000 + Math.floor(i / 3) * 1_000),
    });
  }
  const byCursor = makeDb(withCompletedCalibration(docs, uid));
  const {served} = await walkByCursor(byCursor, uid, {limit: 10});
  assert.equal(new Set(served).size, served.length);
  assert.equal(served.length, 30, `cursor walk reached ${served.length} of 30`);

  const byStoredPosition = makeDb(withCompletedCalibration(docs, uid));
  const {served: rated} = await rateToExhaustion(byStoredPosition, uid, {limit: 10});
  assert.equal(new Set(rated).size, 30, `stored-position walk reached ${rated.length} of 30`);

  const page = await listHumorContentPage(byCursor, {languages: ["tr"], pageSize: 60});
  const first = page.entries[0].position;
  assert.equal(first.nanos % 1_000_000, 250_000 + 9_000, "position lost sub-millisecond precision");
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
    assert.equal(typeof entry.position.seconds, "number");
    assert.equal(typeof entry.position.nanos, "number");
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

  const {served} = await walkByCursor(db, uid);
  for (const blocked of ["hc_0029", "hc_0028", "hc_0027"]) {
    assert.equal(served.includes(blocked), false, `served blocked ${blocked}`);
  }
  assert.equal(served.length, 27);
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

  // Caught up in Turkish is not caught up in English: the proof is per
  // language set, so widening the languages starts a fresh walk.
  markRated(db, uid, idsOf(docs).filter((id) => id.startsWith("hc_")));
  const trOnly = await buildHumorFeed({db, uid, languages: ["tr"], limit: 12});
  assert.equal(trOnly.catalogExhausted, true);
  const both = await buildHumorFeed({db, uid, languages: ["tr", "en"], limit: 12});
  assert.equal(both.catalogExhausted, false);
  assert.equal(both.items.length, 12);
  for (const item of both.items) {
    assert.equal(item.language, "en");
  }
});

test("a forged, corrupt or oversized cursor degrades to the stored position", async () => {
  const uid = "u_cursor";
  const db = makeDb(withCompletedCalibration(catalogOf(40), uid));

  const forged = [
    "",
    "!!!not-base64!!!",
    Buffer.from("{}").toString("base64url"),
    cursorFor(null),
    cursorFor([1, 2]),
    cursorFor("hc_0001"),
    // Out of the Timestamp range: Timestamp.fromMillis used to throw → INTERNAL.
    cursorFor({createdAtMs: 1e20, contentId: "hc_0010"}),
    cursorFor({createdAtMs: -1e20, contentId: "hc_0010"}),
    cursorFor({s: 1e15, n: 0, id: "hc_0010"}),
    cursorFor({s: 1_700_000_000, n: 1_000_000_000, id: "hc_0010"}),
    cursorFor({s: 1_700_000_000.5, n: 0, id: "hc_0010"}),
    // A path separator in the id used to build an odd-segment path → INTERNAL.
    cursorFor({createdAtMs: BASE_MS, contentId: "a/b"}),
    cursorFor({s: 1_700_000_000, n: 0, id: "../users"}),
    cursorFor({s: 1_700_000_000, n: 0, id: "x".repeat(129)}),
    // Longer than any real cursor.
    cursorFor({s: 1_700_000_000, n: 0, id: "hc_0010", pad: "p".repeat(600)}),
  ];
  for (const bad of forged) {
    const result = await feed(db, uid, bad);
    assert.ok(result.items.length > 0, `cursor ${JSON.stringify(bad)} broke the feed`);
  }

  // Oversized or odd language input is capped rather than processed.
  const languages = await buildHumorFeed({
    db,
    uid,
    languages: [...Array(1000)].map(() => "x".repeat(50)),
    limit: 12,
  });
  assert.ok(languages.items.length > 0, "oversized languages must fall back to defaults");
});

test("legacy millisecond cursors still resume without skipping", async () => {
  const uid = "u_legacy_cursor";
  const docs = withCompletedCalibration(catalogOf(40), uid);
  const db = makeDb(docs);
  const boundary = docs["humorContent/hc_0020"].createdAt.toMillis();

  const result = await feed(
    db,
    uid,
    cursorFor({createdAtMs: boundary, contentId: "hc_0020"}),
  );
  const indexes = result.items.map((item) => Number(item.contentId.slice(3)));
  assert.ok(Math.max(...indexes) <= 20, "a legacy cursor jumped back up the catalog");
  assert.ok(indexes.includes(19), "the item right after a legacy cursor was skipped");
  assert.equal(result.items.length, 12);
});

test("calibration owns the page and carries no catalog cursor", async () => {
  // Phase 1 must not couple calibration to the paginated path.
  const uid = "u_calibrating";
  const db = makeDb(curatedCatalog());

  const result = await feed(db, uid);
  assert.equal(result.calibration.complete, false);
  assert.equal(result.items.length > 0, true);
  assert.equal(result.items[0].calibrationStage, "anchor");
  assert.equal(result.nextCursor, null, "calibration pages carry no catalog cursor");
  assert.equal(result.catalogExhausted, false);
});

/** Two curated candidates per anchor slot, carved out of a plain catalog. */
function curatedCatalog() {
  const {ANCHOR_SLOTS, HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");
  const docs = catalogOf(40);
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
  return docs;
}

test("calibration never re-serves a pick the user already rated, skipped or reported", async () => {
  // The selector only knows calibration's own rated ids; anything else the
  // user touched must be caught by the exact per-pick check.
  const uid = "u_calib_seen";
  const db = makeDb(curatedCatalog());
  // A long history that sorts ahead of the catalog ids: the old capped seen
  // prefetch (first 1000 docs) never reached the markers below.
  markRated(
    db,
    uid,
    [...Array(1100)].map((_, i) => `aa_${String(i).padStart(4, "0")}`),
  );

  const before = await feed(db, uid);
  const firstPick = before.items[0].contentId;

  markRated(db, uid, [firstPick], {skipped: true, rating: null});
  const afterSkip = await feed(db, uid);
  const afterSkipIds = afterSkip.items.map((item) => item.contentId);
  assert.equal(afterSkipIds.includes(firstPick), false, "a skipped pick came back");
  assert.equal(afterSkip.items[0].calibrationStage, "anchor");

  // Rated outside calibration (not in ratedContentIds), then reported.
  const secondPick = afterSkip.items[0].contentId;
  markRated(db, uid, [secondPick], {rating: "funny"});
  const thirdPick = afterSkip.items[1]?.contentId;
  if (thirdPick) {
    markRated(db, uid, [thirdPick], {reported: true, skipped: true});
  }
  const seen = new Set([firstPick, secondPick, thirdPick].filter(Boolean));
  const later = await feed(db, uid);
  for (const item of later.items) {
    assert.equal(seen.has(item.contentId), false, `re-served seen ${item.contentId}`);
  }
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
