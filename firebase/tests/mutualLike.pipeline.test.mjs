/**
 * Mutual-like match creation against the real Firestore emulator.
 *
 * The in-memory suites prove the matching *rules*. They cannot prove what
 * broke here: `recordSwipe` ran its transaction as read → write → read, and
 * Firestore rejects a transaction that reads after it writes. Every like
 * returned INTERNAL in production while every unit test stayed green, because
 * no unit test runs a real transaction.
 *
 * This suite drives the same read/write shape through a real transaction, so
 * the ordering constraint is enforced by Firestore rather than by review.
 *
 * Run from the repo root (the rules job already provides the emulator):
 *   npx firebase emulators:exec --only firestore,storage --project mevora-dev \
 *     "npm --prefix firebase/tests test"
 */
import {after, before, describe, it} from "node:test";
import assert from "node:assert/strict";
import {initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  where,
} from "firebase/firestore";

const A = "pipeline_like_a";
const B = "pipeline_like_b";
const likeId = (from, to) => `${from}_${to}`;
const matchIdFor = (a, b) => [a, b].sort().join("_");

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "mevora-mutual-like",
    firestore: {host: "127.0.0.1", port: 8080},
  });
});

after(async () => {
  if (env) await env.cleanup();
});

/**
 * Runs `fn` against an unrestricted Firestore client.
 *
 * Each call opens its own privileged context because the client is terminated
 * when the callback returns — the instance cannot be hoisted out.
 *
 * Rules are proven by the security suite; this file is about the server-side
 * transaction ordering, so it deliberately runs with rules disabled.
 */
async function priv(fn) {
  // withSecurityRulesDisabled resolves to void, so the result is captured here.
  let out;
  await env.withSecurityRulesDisabled(async (ctx) => {
    out = await fn(ctx.firestore());
  });
  return out;
}

/**
 * The transaction shape `recordSwipe` uses, reduced to its reads and writes.
 *
 * Kept deliberately close to the production ordering: if someone reintroduces
 * a read after the write, this throws exactly as the callable did.
 */
function swipe(uid, target, action) {
  return priv((db) => {
    const forwardRef = doc(db, "likes", likeId(uid, target));
    const reverseRef = doc(db, "likes", likeId(target, uid));
    const matchRef = doc(db, "matches", matchIdFor(uid, target));

    return runTransaction(db, async (tx) => {
      const [existing, reverse, matchSnap] = await Promise.all([
        tx.get(forwardRef),
        action === "pass" ? Promise.resolve(null) : tx.get(reverseRef),
        action === "pass" ? Promise.resolve(null) : tx.get(matchRef),
      ]);
      if (existing.exists()) {
        return {matched: false, alreadySwiped: true};
      }
      tx.set(forwardRef, {
        fromUserId: uid,
        toUserId: target,
        action,
        createdAt: serverTimestamp(),
      });
      if (action === "pass" || !reverse || !matchSnap) {
        return {matched: false};
      }
      const positive = reverse.exists() && reverse.data()?.action !== "pass";
      if (!positive) {
        return {matched: false};
      }
      if (matchSnap.exists() && matchSnap.data()?.isActive === true) {
        return {matched: true, matchId: matchRef.id};
      }
      tx.set(matchRef, {
        userIds: [uid, target].sort(),
        createdAt: serverTimestamp(),
        isActive: true,
        unreadCounts: {[uid]: 0, [target]: 0},
        source: "mutual_like",
      });
      return {matched: true, matchId: matchRef.id};
    });
  });
}

const clear = (...paths) =>
  priv(async (db) => {
    for (const p of paths) {
      await deleteDoc(doc(db, ...p.split("/"))).catch(() => undefined);
    }
  });

const exists = (path) => priv(async (db) => (await getDoc(doc(db, ...path.split("/")))).exists());

const readDoc = (path) => priv(async (db) => (await getDoc(doc(db, ...path.split("/")))).data());

const matchesFor = (uid, other) =>
  priv(async (db) => {
    const snap = await getDocs(
      query(collection(db, "matches"), where("userIds", "array-contains", uid)),
    );
    return snap.docs
      .filter((d) => (d.data().userIds ?? []).includes(other))
      .map((d) => ({id: d.id, ...d.data()}));
  });

describe("mutual like transaction (real Firestore)", () => {
  before(async () => {
    await clear(
      `likes/${likeId(A, B)}`,
      `likes/${likeId(B, A)}`,
      `matches/${matchIdFor(A, B)}`,
    );
  });

  it("a one-sided like commits without creating a match", async () => {
    // This is the assertion that failed in production: the transaction threw
    // "transactions require all reads to be executed before all writes".
    const first = await swipe(A, B, "like");
    assert.equal(first.matched, false);
    assert.equal(
      await exists(`likes/${likeId(A, B)}`),
      true,
      "the like document must be committed",
    );
    assert.equal(
      await exists(`matches/${matchIdFor(A, B)}`),
      false,
      "no match before the like is mutual",
    );
  });

  it("the reciprocal like creates exactly one active match", async () => {
    const second = await swipe(B, A, "like");
    assert.equal(second.matched, true);
    assert.equal(second.matchId, matchIdFor(A, B));

    const pair = await matchesFor(A, B);
    assert.equal(pair.length, 1, `expected 1 match, found ${pair.length}`);
    assert.equal(pair[0].isActive, true);
    assert.deepEqual(pair[0].userIds, [A, B].sort());
  });

  it("replaying either like leaves a single match", async () => {
    await swipe(A, B, "like");
    await swipe(B, A, "like");
    const pair = await matchesFor(A, B);
    assert.equal(pair.length, 1, "a replayed like must not duplicate the match");
  });

  it("a pass commits without reading the reverse like", async () => {
    const C = "pipeline_like_c";
    await clear(`likes/${likeId(A, C)}`);
    const result = await swipe(A, C, "pass");
    assert.equal(result.matched, false);
    assert.equal((await readDoc(`likes/${likeId(A, C)}`))?.action, "pass");
    await clear(`likes/${likeId(A, C)}`);
  });

  it("concurrent reciprocal likes still yield one match", async () => {
    const X = "pipeline_race_x";
    const Y = "pipeline_race_y";
    await clear(
      `likes/${likeId(X, Y)}`,
      `likes/${likeId(Y, X)}`,
      `matches/${matchIdFor(X, Y)}`,
    );
    // Both directions at once: Firestore's transaction retry must serialise
    // them rather than producing two match documents.
    await Promise.all([swipe(X, Y, "like"), swipe(Y, X, "like")]);
    const pair = await matchesFor(X, Y);
    assert.equal(pair.length, 1, `concurrent likes produced ${pair.length} matches`);
  });
});
