const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {swipeTransaction} = require("../lib/social.js");

/**
 * A transaction that enforces what Firestore enforces.
 *
 * `recordSwipe` shipped with its transaction ordered read → write → read.
 * Firestore rejects that ("all reads must be executed before all writes"), so
 * every like returned INTERNAL — and all 510 backend tests stayed green,
 * because none of them ran a transaction. This fake closes that gap: it fails
 * the moment the production body reads after it writes.
 */
class StrictTransaction {
  constructor(docs = {}) {
    this.docs = docs;
    this.writes = [];
    this.reads = [];
    this.hasWritten = false;
  }

  async get(ref) {
    if (this.hasWritten) {
      throw new Error(
        "Firestore transactions require all reads to be executed before all writes.",
      );
    }
    this.reads.push(ref.path);
    const data = this.docs[ref.path];
    return {
      exists: data !== undefined,
      data: () => data,
      ref,
    };
  }

  set(ref, value) {
    this.hasWritten = true;
    this.writes.push({path: ref.path, value});
  }
}

const ref = (path) => ({path, id: path.split("/").pop()});

const PREVIEW_A = {name: "User A", photoUrl: "https://img/a.jpg", isVerified: false};
const PREVIEW_B = {name: "User B", isVerified: true};

function input(overrides = {}) {
  return {
    uid: "user_a",
    targetUserId: "user_b",
    action: "like",
    matchId: "user_a_user_b",
    forwardRef: ref("likes/user_a_user_b"),
    reverseRef: ref("likes/user_b_user_a"),
    matchRef: ref("matches/user_a_user_b"),
    loadPreviews: async () => [PREVIEW_A, PREVIEW_B],
    ...overrides,
  };
}

describe("recordSwipe transaction ordering", () => {
  it("performs every read before its first write", async () => {
    // The regression guard. If a read is reintroduced after the write, the
    // fake throws exactly as Firestore does.
    const tx = new StrictTransaction();
    await swipeTransaction(tx, input());
    assert.ok(tx.reads.length >= 1, "expected the like document to be read");
    assert.ok(tx.writes.length >= 1, "expected the like document to be written");
  });

  it("performs every read before its first write on the matching like", async () => {
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {fromUserId: "user_b", toUserId: "user_a", action: "like"},
    });
    const result = await swipeTransaction(tx, input());
    assert.equal(result.matched, true);
  });

  it("performs every read before its first write on a pass", async () => {
    const tx = new StrictTransaction();
    const result = await swipeTransaction(tx, input({action: "pass"}));
    assert.equal(result.matched, false);
  });
});

describe("recordSwipe transaction outcomes", () => {
  it("a one-sided like writes the like and creates no match", async () => {
    const tx = new StrictTransaction();
    const result = await swipeTransaction(tx, input());

    assert.equal(result.matched, false);
    assert.deepEqual(
      tx.writes.map((w) => w.path),
      ["likes/user_a_user_b"],
      "only the like document may be written",
    );
  });

  it("a pass writes the pass and never looks at the reverse like", async () => {
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {action: "like"},
    });
    const result = await swipeTransaction(tx, input({action: "pass"}));

    assert.equal(result.matched, false);
    assert.equal(tx.writes[0].value.action, "pass");
    assert.equal(
      tx.reads.includes("matches/user_a_user_b"),
      false,
      "a pass must not read the match document",
    );
  });

  it("a reciprocated like creates the match with both participants", async () => {
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {fromUserId: "user_b", toUserId: "user_a", action: "like"},
    });
    const result = await swipeTransaction(tx, input());

    assert.equal(result.matched, true);
    assert.equal(result.matchId, "user_a_user_b");
    const match = tx.writes.find((w) => w.path === "matches/user_a_user_b");
    assert.ok(match, "the match document must be written");
    assert.deepEqual(match.value.userIds, ["user_a", "user_b"]);
    assert.equal(match.value.isActive, true);
    assert.equal(match.value.source, "mutual_like");
    assert.deepEqual(match.value.unreadCounts, {user_a: 0, user_b: 0});
  });

  it("stores the real participant names, not the fallback", async () => {
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {action: "like"},
    });
    await swipeTransaction(tx, input());
    const match = tx.writes.find((w) => w.path === "matches/user_a_user_b");
    assert.deepEqual(match.value.participantNames, {
      user_a: "User A",
      user_b: "User B",
    });
    assert.notEqual(match.value.participantNames.user_a, "Mevora");
  });

  it("omits a photo entry for a participant without one", async () => {
    const tx = new StrictTransaction({"likes/user_b_user_a": {action: "like"}});
    await swipeTransaction(tx, input());
    const match = tx.writes.find((w) => w.path === "matches/user_a_user_b");
    assert.deepEqual(Object.keys(match.value.participantPhotos), ["user_a"]);
  });

  it("a reverse pass is not mutual interest", async () => {
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {fromUserId: "user_b", toUserId: "user_a", action: "pass"},
    });
    const result = await swipeTransaction(tx, input());
    assert.equal(result.matched, false);
    assert.equal(
      tx.writes.some((w) => w.path.startsWith("matches/")),
      false,
      "a pass from the other side must not create a match",
    );
  });

  it("an already-swiped like is rejected without writing", async () => {
    const tx = new StrictTransaction({
      "likes/user_a_user_b": {fromUserId: "user_a", toUserId: "user_b", action: "like"},
    });
    await assert.rejects(
      () => swipeTransaction(tx, input()),
      (error) => error.code === "already-exists",
    );
    assert.deepEqual(tx.writes, [], "a rejected swipe must write nothing");
  });

  it("an existing active match short-circuits without rewriting it", async () => {
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {action: "like"},
      "matches/user_a_user_b": {userIds: ["user_a", "user_b"], isActive: true},
    });
    const result = await swipeTransaction(tx, input());
    assert.deepEqual(result, {matched: true, matchId: "user_a_user_b"});
    assert.equal(
      tx.writes.some((w) => w.path.startsWith("matches/")),
      false,
      "an active match must not be overwritten",
    );
  });

  it("a re-match preserves the original createdAt", async () => {
    const original = "2026-01-01T00:00:00Z";
    const tx = new StrictTransaction({
      "likes/user_b_user_a": {action: "like"},
      "matches/user_a_user_b": {
        userIds: ["user_a", "user_b"],
        isActive: false,
        createdAt: original,
      },
    });
    await swipeTransaction(tx, input());
    const match = tx.writes.find((w) => w.path === "matches/user_a_user_b");
    assert.equal(match.value.createdAt, original, "re-match must not reset createdAt");
    assert.equal(match.value.isActive, true);
    assert.equal(match.value.unmatchedBy, null);
  });
});
