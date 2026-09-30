const {afterEach, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {logger} = require("firebase-functions");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs} = require("./helpers/adminStubs.cjs");

const fake = createFakeFirestore();
const meter = {reads: 0, queries: []};

/**
 * Bills queries the way Firestore does — one read per returned document,
 * at least one per query — and can make the (status, expiresAt) query fail
 * the way it does while its composite index is not deployed.
 */
let failExpiresAtQuery = null;
function meteredQuery(query, filters = []) {
  return {
    where: (field, op, value) => meteredQuery(query.where(field, op, value), [...filters, [field, op, value]]),
    orderBy: (...args) => meteredQuery(query.orderBy(...args), filters),
    limit: (n) => meteredQuery(query.limit(n), filters),
    startAfter: (...args) => meteredQuery(query.startAfter(...args), filters),
    get: async () => {
      if (failExpiresAtQuery && filters.some(([field]) => field === "expiresAt")) {
        throw failExpiresAtQuery;
      }
      const snap = await query.get();
      meter.reads += Math.max(1, snap.docs.length);
      meter.queries.push({filters, returned: snap.docs.length});
      return snap;
    },
  };
}
const db = {
  ...fake,
  collectionGroup: (id) => meteredQuery(fake.collectionGroup(id)),
  // sendUserPush writes an in-app notification row; the double has no add().
  collection: (path) => {
    const ref = fake.collection(path);
    if (path !== "notifications") return ref;
    return {...ref, add: async (data) => {
      const doc = ref.doc(`n${fake.paths().filter((p) => p.startsWith("notifications/")).length + 1}`);
      await doc.set(data);
      return doc;
    }};
  },
};
installFirebaseAdminStubs({db});

const {expireDueBoosts, isMissingIndexError, EXPIRY_PAGE_SIZE} = require("../lib/boost/expiry.js");
const {expireBoost} = require("../lib/boost/verifyBoostPurchase.js");

const NOW = Timestamp.fromMillis(Date.UTC(2026, 8, 30, 12, 0, 0));
const MINUTE = 60 * 1000;
const DAY = 24 * 60 * MINUTE;

function boost(uid, id, expiresInMs, status = "active") {
  return {
    [`users/${uid}/boosts/${id}`]: {
      boostId: id,
      userId: uid,
      productId: "boost_week",
      status,
      startedAt: Timestamp.fromMillis(NOW.toMillis() - DAY),
      expiresAt: Timestamp.fromMillis(NOW.toMillis() + expiresInMs),
    },
  };
}

/** `live` Boosts that run for weeks, plus the given due ones. */
function seed(live, ...extra) {
  const docs = {};
  for (let i = 0; i < live; i++) Object.assign(docs, boost(`live${i}`, `b${i}`, 7 * DAY));
  for (const e of extra) Object.assign(docs, e);
  fake.reset(docs);
  meter.reads = 0;
  meter.queries = [];
}

const status = (uid, id) => fake.read(`users/${uid}/boosts/${id}`).status;

let pushes;
let infoLogs;
let warnLogs;
const originalInfo = logger.info;
const originalWarn = logger.warn;
const notify = async (item) => {
  pushes.push(item);
};

beforeEach(() => {
  pushes = [];
  infoLogs = [];
  warnLogs = [];
  failExpiresAtQuery = null;
  logger.info = (message, data) => infoLogs.push([message, data]);
  logger.warn = (message, data) => warnLogs.push([message, data]);
});
afterEach(() => {
  logger.info = originalInfo;
  logger.warn = originalWarn;
});

function indexMissing() {
  const error = new Error("9 FAILED_PRECONDITION: The query requires an index. You can create it here: https://...");
  error.code = 9;
  return error;
}

describe("expireDueBoosts", () => {
  it("expires only the due Boosts, and bills reads for those alone", async () => {
    seed(
      200,
      boost("ayse", "due1", -5 * MINUTE),
      boost("mert", "due2", 0), // expiresAt == now counts as over
      boost("cem", "done", -DAY, "expired"),
    );

    const result = await expireDueBoosts(db, {now: NOW, notify});

    assert.deepEqual(result, {expired: 2, pages: 1, usedFallback: false});
    assert.equal(status("ayse", "due1"), "expired");
    assert.equal(status("mert", "due2"), "expired");
    assert.equal(status("cem", "done"), "expired");
    assert.equal(status("live0", "b0"), "active");
    assert.equal(status("live199", "b199"), "active");
    // The old scan read all 202 active Boosts; this reads the 2 due ones.
    assert.equal(meter.reads, 2);
    assert.deepEqual(meter.queries[0].filters, [
      ["status", "==", "active"],
      ["expiresAt", "<=", NOW],
    ]);
  });

  it("costs one read when nothing is due, however many Boosts are live", async () => {
    seed(500);

    const result = await expireDueBoosts(db, {now: NOW, notify});

    assert.deepEqual(result, {expired: 0, pages: 1, usedFallback: false});
    assert.equal(meter.reads, 1);
    assert.deepEqual(pushes, []);
    assert.deepEqual(infoLogs, []);
  });

  it("logs and notifies each expired Boost exactly as before", async () => {
    seed(3, boost("ayse", "due1", -MINUTE), boost("mert", "due2", -2 * MINUTE));

    await expireDueBoosts(db, {now: NOW, notify});

    const byId = (a, b) => (a.boostId < b.boostId ? -1 : 1);
    assert.deepEqual(
      infoLogs.filter(([m]) => m === "boost_expired").map(([, d]) => d).sort(byId),
      [{userId: "ayse", boostId: "due1"}, {userId: "mert", boostId: "due2"}],
    );
    assert.deepEqual([...pushes].sort(byId), [
      {uid: "ayse", boostId: "due1"},
      {uid: "mert", boostId: "due2"},
    ]);
  });

  it("notifies only after the write has landed", async () => {
    seed(0, boost("ayse", "due1", -MINUTE));
    const seenAtPush = [];

    await expireDueBoosts(db, {
      now: NOW,
      notify: async (item) => {
        seenAtPush.push(status(item.uid, item.boostId));
      },
    });

    assert.deepEqual(seenAtPush, ["expired"]);
  });

  it("skips the push for a Boost without an owner id, but still expires it", async () => {
    seed(0, {"users/ghost/boosts/orphan": {status: "active", expiresAt: Timestamp.fromMillis(NOW.toMillis() - MINUTE)}});

    await expireDueBoosts(db, {now: NOW, notify});

    assert.equal(status("ghost", "orphan"), "expired");
    assert.deepEqual(pushes, []);
    assert.deepEqual(infoLogs, [["boost_expired", {userId: undefined, boostId: "orphan"}]]);
  });

  it("pages through a backlog larger than one page, each page in its own batch", async () => {
    const due = [];
    for (let i = 0; i < 7; i++) due.push(boost(`u${i}`, `due${i}`, -(i + 1) * MINUTE));
    seed(50, ...due);

    const result = await expireDueBoosts(db, {now: NOW, notify, pageSize: 3});

    // 3 + 3 + 1: the short last page ends the run.
    assert.deepEqual(result, {expired: 7, pages: 3, usedFallback: false});
    assert.deepEqual(meter.queries.map((q) => q.returned), [3, 3, 1]);
    for (let i = 0; i < 7; i++) assert.equal(status(`u${i}`, `due${i}`), "expired");
    assert.equal(pushes.length, 7);
    assert.equal(meter.reads, 7);
  });

  it("reads one extra empty page when the backlog is an exact multiple of the page", async () => {
    seed(10, boost("a", "d1", -MINUTE), boost("b", "d2", -MINUTE));

    const result = await expireDueBoosts(db, {now: NOW, notify, pageSize: 2});

    assert.deepEqual(result, {expired: 2, pages: 2, usedFallback: false});
    assert.deepEqual(meter.queries.map((q) => q.returned), [2, 0]);
  });

  it("stops at the page cap and leaves the rest for the next run", async () => {
    const due = [];
    for (let i = 0; i < 5; i++) due.push(boost(`u${i}`, `due${i}`, -(i + 1) * MINUTE));
    seed(0, ...due);

    const result = await expireDueBoosts(db, {now: NOW, notify, pageSize: 2, maxPages: 2});

    assert.deepEqual(result, {expired: 4, pages: 2, usedFallback: false});
    assert.equal(fake.paths().filter((p) => fake.read(p).status === "active").length, 1);
    assert.deepEqual(warnLogs, [["boost_expiry_backlog", {pages: 2, expired: 4, pageSize: 2}]]);

    // The next run picks up the remainder.
    await expireDueBoosts(db, {now: NOW, notify, pageSize: 2, maxPages: 2});
    assert.equal(fake.paths().filter((p) => fake.read(p).status === "active").length, 0);
  });

  it("uses a page size that fits one write batch", () => {
    assert.ok(EXPIRY_PAGE_SIZE > 0 && EXPIRY_PAGE_SIZE <= 500);
  });
});

describe("expireDueBoosts without the composite index", () => {
  it("logs a warning and falls back to the full scan, with the same outcome", async () => {
    seed(20, boost("ayse", "due1", -MINUTE), boost("mert", "due2", 0), boost("cem", "done", -DAY, "expired"));
    failExpiresAtQuery = indexMissing();

    const result = await expireDueBoosts(db, {now: NOW, notify});

    assert.deepEqual(result, {expired: 2, pages: 0, usedFallback: true});
    assert.equal(status("ayse", "due1"), "expired");
    assert.equal(status("mert", "due2"), "expired");
    assert.equal(status("live0", "b0"), "active");
    assert.equal(warnLogs.length, 1);
    assert.equal(warnLogs[0][0], "boost_expiry_index_missing");
    assert.equal(warnLogs[0][1].fallback, "full_scan");
    // The fallback is the old scan: one status-only query over every active Boost.
    assert.deepEqual(meter.queries.map((q) => q.filters), [[["status", "==", "active"]]]);
    assert.equal(meter.reads, 22);
    assert.deepEqual(
      pushes.map((p) => p.boostId).sort(),
      ["due1", "due2"],
    );
  });

  it("splits a large fallback into batches under the write limit", async () => {
    const due = [];
    for (let i = 0; i < 5; i++) due.push(boost(`u${i}`, `due${i}`, -MINUTE));
    seed(3, ...due);
    failExpiresAtQuery = indexMissing();
    let commits = 0;
    const realBatch = fake.batch;
    const countingDb = {...db, batch: () => {
      const b = realBatch();
      const commit = b.commit.bind(b);
      b.commit = async () => {
        commits += 1;
        return commit();
      };
      return b;
    }};

    const result = await expireDueBoosts(countingDb, {now: NOW, notify, pageSize: 2});

    assert.equal(result.expired, 5);
    assert.equal(commits, 3);
    assert.equal(pushes.length, 5);
  });

  it("does not hide other query failures behind the fallback", async () => {
    seed(5, boost("ayse", "due1", -MINUTE));
    const error = new Error("14 UNAVAILABLE: backend down");
    error.code = 14;
    failExpiresAtQuery = error;

    await assert.rejects(expireDueBoosts(db, {now: NOW, notify}), /UNAVAILABLE/);
    assert.equal(status("ayse", "due1"), "active");
    assert.deepEqual(warnLogs, []);
  });

  it("recognises the missing-index error in each shape the SDKs use", () => {
    assert.equal(isMissingIndexError(indexMissing()), true);
    assert.equal(isMissingIndexError({code: "failed-precondition"}), true);
    assert.equal(isMissingIndexError({code: "FAILED_PRECONDITION"}), true);
    assert.equal(isMissingIndexError({code: 14}), false);
    assert.equal(isMissingIndexError(null), false);
    assert.equal(isMissingIndexError(new Error("boom")), false);
  });
});

describe("expireBoost (scheduled)", () => {
  it("expires due Boosts and sends the boostExpired notification to each owner", async () => {
    // Real clock: the scheduled handler reads Timestamp.now().
    const now = Date.now();
    fake.reset({
      "users/ayse/boosts/due1": {userId: "ayse", status: "active", expiresAt: Timestamp.fromMillis(now - MINUTE)},
      "users/mert/boosts/live": {userId: "mert", status: "active", expiresAt: Timestamp.fromMillis(now + DAY)},
      "userSettings/ayse": {languageCode: "tr"},
    });

    await expireBoost.run({scheduleTime: new Date(now).toISOString()});

    assert.equal(status("ayse", "due1"), "expired");
    assert.equal(status("mert", "live"), "active");
    const rows = fake.paths().filter((p) => p.startsWith("notifications/")).map((p) => fake.read(p));
    assert.equal(rows.length, 1);
    assert.equal(rows[0].userId, "ayse");
    assert.equal(rows[0].type, "boostExpired");
    assert.equal(rows[0].body, "Boost süresi doldu");
    assert.deepEqual(infoLogs.filter(([m]) => m === "boost_expired"), [
      ["boost_expired", {userId: "ayse", boostId: "due1"}],
    ]);
  });
});
