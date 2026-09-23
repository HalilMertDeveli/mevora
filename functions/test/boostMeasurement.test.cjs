const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  viewerKey,
  boostReachPath,
  boostSessionPath,
  classifyImpression,
  metricsFromDocument,
  recordBoostImpressions,
  attributeBoostEvent,
  ZERO_METRICS,
} = require("../lib/boost/measurement.js");

const NOW = new Date("2026-09-22T12:00:00.000Z");
const LATER = new Date("2026-09-22T12:30:00.000Z");
const EARLIER = new Date("2026-09-22T11:30:00.000Z");

function session(userId, boostId = "boost_1", expiresAt = LATER) {
  return {boostId, userId, startedAt: EARLIER, expiresAt};
}

/**
 * Minimal in-memory Firestore stand-in: enough for getAll, batch and
 * runTransaction, so the counting rules are exercised without an emulator.
 */
function fakeDb(seed = {}) {
  const docs = new Map(Object.entries(seed));
  const db = {
    writes: [],
    commits: 0,
    transactions: 0,
    doc(p) {
      return {
        path: p,
        get exists() {
          return docs.has(p);
        },
      };
    },
    async getAll(...refs) {
      return refs.map((ref) => ({
        exists: docs.has(ref.path),
        data: () => docs.get(ref.path),
      }));
    },
    batch() {
      const ops = [];
      return {
        set(ref, data) {
          ops.push({op: "set", path: ref.path, data});
        },
        update(ref, data) {
          ops.push({op: "update", path: ref.path, data});
        },
        async commit() {
          db.commits += 1;
          db.writes.push(...ops);
          for (const o of ops) {
            const prev = docs.get(o.path) ?? {};
            docs.set(o.path, {...prev, ...o.data});
          }
        },
      };
    },
    async runTransaction(fn) {
      db.transactions += 1;
      const ops = [];
      const tx = {
        async get(ref) {
          return {exists: docs.has(ref.path), data: () => docs.get(ref.path)};
        },
        update(ref, data) {
          ops.push({op: "update", path: ref.path, data});
        },
        set(ref, data) {
          ops.push({op: "set", path: ref.path, data});
        },
      };
      const result = await fn(tx);
      db.writes.push(...ops);
      for (const o of ops) {
        const prev = docs.get(o.path) ?? {};
        docs.set(o.path, {...prev, ...o.data});
      }
      return result;
    },
    _docs: docs,
  };
  return db;
}

describe("viewer key privacy", () => {
  it("is deterministic for the same pair", () => {
    assert.equal(viewerKey("viewer", "boosted"), viewerKey("viewer", "boosted"));
  });

  it("differs per boosted profile, so rows cannot be joined into a history", () => {
    assert.notEqual(viewerKey("viewer", "a"), viewerKey("viewer", "b"));
  });

  it("never contains the raw viewer uid", () => {
    const key = viewerKey("viewer-uid-123", "boosted");
    assert.equal(key.includes("viewer-uid-123"), false);
    assert.equal(key.length, 32);
  });
});

describe("impression classification", () => {
  it("1/4. a first sighting is an impression and a unique reach", () => {
    assert.deepEqual(classifyImpression(undefined, session("u")), {
      isNewSession: true,
      countsAsUnique: true,
    });
  });

  it("3/4. the same viewer again in the same session is not unique", () => {
    const existing = {boostId: "boost_1", impressions: 1};
    assert.deepEqual(classifyImpression(existing, session("u", "boost_1")), {
      isNewSession: false,
      countsAsUnique: false,
    });
  });

  it("a returning viewer in a NEW session counts as unique again", () => {
    const existing = {boostId: "boost_1", impressions: 4};
    assert.deepEqual(classifyImpression(existing, session("u", "boost_2")), {
      isNewSession: true,
      countsAsUnique: true,
    });
  });
});

describe("recordBoostImpressions", () => {
  it("1. a boosted profile on the response page is counted", async () => {
    const db = fakeDb();
    const sessions = new Map([["boosted", session("boosted")]]);
    const result = await recordBoostImpressions({
      db, viewerUid: "viewer", shownUids: ["boosted", "plain"], sessions, now: NOW,
    });
    assert.equal(result.impressions, 1);
    assert.equal(result.newUniqueReach, 1);
    const counter = db.writes.find((w) => w.path === boostSessionPath("boosted", "boost_1"));
    assert.ok(counter, "session counters must be written");
  });

  it("2/5. a non-boosted profile produces no Boost impression", async () => {
    const db = fakeDb();
    const result = await recordBoostImpressions({
      db, viewerUid: "viewer", shownUids: ["plain_a", "plain_b"],
      sessions: new Map(), now: NOW,
    });
    assert.equal(result.impressions, 0);
    assert.equal(db.commits, 0, "no write at all when nothing is boosted");
  });

  it("6. an expired Boost produces no impression", async () => {
    const db = fakeDb();
    const sessions = new Map([["boosted", session("boosted", "boost_1", EARLIER)]]);
    const result = await recordBoostImpressions({
      db, viewerUid: "viewer", shownUids: ["boosted"], sessions, now: NOW,
    });
    assert.equal(result.impressions, 0);
    assert.equal(db.commits, 0);
  });

  it("3/4. a repeat view adds an impression but not a unique reach", async () => {
    const key = viewerKey("viewer", "boosted");
    const db = fakeDb({
      [boostReachPath("boosted", key)]: {boostId: "boost_1", impressions: 1},
    });
    const sessions = new Map([["boosted", session("boosted")]]);
    const result = await recordBoostImpressions({
      db, viewerUid: "viewer", shownUids: ["boosted"], sessions, now: NOW,
    });
    assert.equal(result.impressions, 1);
    assert.equal(result.newUniqueReach, 0);
  });

  it("a viewer never counts as reaching themselves", async () => {
    const db = fakeDb();
    const sessions = new Map([["viewer", session("viewer")]]);
    const result = await recordBoostImpressions({
      db, viewerUid: "viewer", shownUids: ["viewer"], sessions, now: NOW,
    });
    assert.equal(result.impressions, 0);
  });

  it("a duplicated uid on one page is counted once", async () => {
    const db = fakeDb();
    const sessions = new Map([["boosted", session("boosted")]]);
    const result = await recordBoostImpressions({
      db, viewerUid: "viewer", shownUids: ["boosted", "boosted", "boosted"],
      sessions, now: NOW,
    });
    assert.equal(result.impressions, 1);
  });

  it("cost: one batched read and one commit regardless of page size", async () => {
    const db = fakeDb();
    const sessions = new Map();
    const shown = [];
    for (let i = 0; i < 7; i += 1) {
      sessions.set(`b${i}`, session(`b${i}`));
      shown.push(`b${i}`);
    }
    await recordBoostImpressions({db, viewerUid: "viewer", shownUids: shown, sessions, now: NOW});
    assert.equal(db.commits, 1, "must be a single batched commit");
  });

  it("7. a measurement failure never breaks the Discover response", async () => {
    const broken = fakeDb();
    broken.getAll = async () => {
      throw new Error("firestore unavailable");
    };
    const sessions = new Map([["boosted", session("boosted")]]);
    const result = await recordBoostImpressions({
      db: broken, viewerUid: "viewer", shownUids: ["boosted"], sessions, now: NOW,
    });
    assert.deepEqual(result, {impressions: 0, newUniqueReach: 0});
  });
});

describe("attribution", () => {
  const key = viewerKey("viewer", "boosted");
  const reachPath = boostReachPath("boosted", key);

  const seenReach = () => ({
    [reachPath]: {boostId: "boost_1", boostExpiresAt: LATER, impressions: 1},
  });

  it("8. a like from someone who saw the boosted profile is attributed", async () => {
    const db = fakeDb(seenReach());
    const result = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "like", now: NOW,
    });
    assert.equal(result.outcome, "attributed");
    assert.equal(result.boostId, "boost_1");
    const counter = db.writes.find((w) => w.path === boostSessionPath("boosted", "boost_1"));
    assert.ok(counter.data.likesReceived, "likesReceived must be incremented");
  });

  it("9/13. a duplicate like is counted once", async () => {
    const db = fakeDb(seenReach());
    const first = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "like", now: NOW,
    });
    const second = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "like", now: NOW,
    });
    assert.equal(first.outcome, "attributed");
    assert.equal(second.outcome, "already_counted");
  });

  it("10/11/14. a like from someone who never saw the profile is not attributed", async () => {
    const db = fakeDb();
    const result = await attributeBoostEvent({
      db, viewerUid: "stranger", boostedUid: "boosted", kind: "like", now: NOW,
    });
    assert.equal(result.outcome, "no_reach");
    assert.equal(db.writes.length, 0);
  });

  it("10. a like after the Boost ended is not attributed", async () => {
    const db = fakeDb({
      [reachPath]: {boostId: "boost_1", boostExpiresAt: EARLIER, impressions: 1},
    });
    const result = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "like", now: NOW,
    });
    assert.equal(result.outcome, "boost_ended");
    assert.equal(db.writes.length, 0);
  });

  it("12. a match is attributed and 13. counted once", async () => {
    const db = fakeDb(seenReach());
    const first = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "match", now: NOW,
    });
    const second = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "match", now: NOW,
    });
    assert.equal(first.outcome, "attributed");
    assert.equal(second.outcome, "already_counted");
    const counter = db.writes.find((w) => w.path === boostSessionPath("boosted", "boost_1"));
    assert.ok(counter.data.matchesCreated);
  });

  it("likes and matches are tracked independently", async () => {
    const db = fakeDb(seenReach());
    const like = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "like", now: NOW,
    });
    const match = await attributeBoostEvent({
      db, viewerUid: "viewer", boostedUid: "boosted", kind: "match", now: NOW,
    });
    assert.equal(like.outcome, "attributed");
    assert.equal(match.outcome, "attributed");
  });

  it("self-attribution is refused", async () => {
    const db = fakeDb();
    const result = await attributeBoostEvent({
      db, viewerUid: "same", boostedUid: "same", kind: "like", now: NOW,
    });
    assert.equal(result.outcome, "no_reach");
    assert.equal(db.transactions, 0);
  });
});

describe("17. truthful zero summary", () => {
  it("a Boost with no activity reads as explicit zeroes", () => {
    assert.deepEqual(metricsFromDocument(undefined), ZERO_METRICS);
    assert.deepEqual(metricsFromDocument({}), ZERO_METRICS);
  });

  it("negative or malformed counters never become positive", () => {
    const metrics = metricsFromDocument({
      totalImpressions: -5,
      uniqueUsersReached: "many",
      likesReceived: null,
      matchesCreated: 3.7,
    });
    assert.equal(metrics.totalImpressions, 0);
    assert.equal(metrics.uniqueUsersReached, 0);
    assert.equal(metrics.likesReceived, 0);
    assert.equal(metrics.matchesCreated, 3);
  });
});

describe("18-20. security boundaries", () => {
  const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firebase", "firestore.rules"),
    "utf8",
  );

  it("18/20. the owner may read boost counters but nobody may write them", () => {
    const at = rules.indexOf("match /boosts/{boostId}");
    assert.ok(at > -1);
    const block = rules.slice(at, at + 200);
    assert.ok(block.includes("allow read: if isOwner(userId)"));
    assert.ok(block.includes("allow create, update, delete: if false"));
  });

  it("19. per-viewer reach rows are unreadable by any client", () => {
    const at = rules.indexOf("match /boostReach/{viewerKey}");
    assert.ok(at > -1, "boostReach must have an explicit rule");
    const block = rules.slice(at, at + 160);
    assert.ok(block.includes("allow read, create, update, delete: if false"));
  });

  it("measurement is written only by the backend, never by a callable input", () => {
    const measurement = fs.readFileSync(
      path.join(__dirname, "..", "src", "boost", "measurement.ts"),
      "utf8",
    );
    assert.equal(measurement.includes("onCall("), false);
    assert.equal(measurement.includes("onRequest("), false);
    const backend = fs.readFileSync(
      path.join(__dirname, "..", "src", "backend.ts"),
      "utf8",
    );
    // The page measured is the server's own response, never a client-supplied list.
    assert.ok(backend.includes("shownUids: filled.items.map("));
    assert.equal(backend.includes("request.data?.shownUids"), false);
    assert.equal(backend.includes("request.data?.impressions"), false);
  });
});

describe("paths", () => {
  it("keeps the documented layout", () => {
    assert.equal(boostSessionPath("u1", "b1"), "users/u1/boosts/b1");
    assert.equal(boostReachPath("u1", "k1"), "users/u1/boostReach/k1");
  });
});
