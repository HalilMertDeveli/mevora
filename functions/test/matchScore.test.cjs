const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  INITIAL_MATCH_SCORE,
  INTERACTION_WINDOW_MS,
  seedScore,
  shouldAwardMatchBonus,
  shouldAwardInteractionBonus,
  sanitizeFeedback,
  canSubmitFeedback,
} = require("../lib/matchScore.js");

const now = Date.UTC(2026, 7, 20, 12);
const matchedAt = now;
const userIds = ["aya", "can"];

describe("match score policy", () => {
  it("new users start at 50", () => {
    assert.equal(INITIAL_MATCH_SCORE, 50);
    assert.equal(seedScore(undefined), 50);
    assert.equal(seedScore(null), 50);
    assert.equal(seedScore(50), 50);
    assert.equal(seedScore(51), 51);
  });

  it("unique match awards +1 once", () => {
    assert.equal(shouldAwardMatchBonus(false), true);
    assert.equal(shouldAwardMatchBonus(undefined), true);
    assert.equal(shouldAwardMatchBonus(true), false);
    assert.equal(seedScore(50) + 1, 51);
  });

  it("two-way messaging in the window awards +1 once", () => {
    assert.equal(
      shouldAwardInteractionBonus({
        alreadyAwarded: false,
        matchedAtMs: matchedAt,
        nowMs: now + 2 * 86400000,
        messagedUserIds: ["aya", "can"],
        userIds,
      }),
      true,
    );
    assert.equal(
      shouldAwardInteractionBonus({
        alreadyAwarded: true,
        matchedAtMs: matchedAt,
        nowMs: now + 2 * 86400000,
        messagedUserIds: ["aya", "can"],
        userIds,
      }),
      false,
    );
  });

  it("spam still awards only one interaction bonus", () => {
    const many = Array.from({length: 50}, (_, i) => (i % 2 === 0 ? "aya" : "can"));
    assert.equal(
      shouldAwardInteractionBonus({
        alreadyAwarded: false,
        matchedAtMs: matchedAt,
        nowMs: now,
        messagedUserIds: many,
        userIds,
      }),
      true,
    );
    assert.equal(
      shouldAwardInteractionBonus({
        alreadyAwarded: true,
        matchedAtMs: matchedAt,
        nowMs: now,
        messagedUserIds: many,
        userIds,
      }),
      false,
    );
  });

  it("after 3 days no interaction bonus", () => {
    assert.equal(INTERACTION_WINDOW_MS, 3 * 24 * 60 * 60 * 1000);
    assert.equal(
      shouldAwardInteractionBonus({
        alreadyAwarded: false,
        matchedAtMs: matchedAt,
        nowMs: now + INTERACTION_WINDOW_MS + 1,
        messagedUserIds: ["aya", "can"],
        userIds,
      }),
      false,
    );
  });

  it("one-way messages are not meaningful two-way", () => {
    assert.equal(
      shouldAwardInteractionBonus({
        alreadyAwarded: false,
        matchedAtMs: matchedAt,
        nowMs: now,
        messagedUserIds: ["aya"],
        userIds,
      }),
      false,
    );
  });

  it("feedback does not change scores and is private-author only", () => {
    const score = seedScore(51);
    assert.equal(score, 51);
    assert.equal(
      canSubmitFeedback({
        uid: "can",
        isActive: false,
        unmatchedBy: "aya",
        alreadySubmitted: false,
      }),
      true,
    );
    assert.equal(
      canSubmitFeedback({
        uid: "aya",
        isActive: false,
        unmatchedBy: "aya",
        alreadySubmitted: false,
      }),
      false,
    );
    assert.equal(
      canSubmitFeedback({
        uid: "can",
        isActive: true,
        unmatchedBy: null,
        alreadySubmitted: false,
      }),
      false,
    );
    assert.equal(
      canSubmitFeedback({
        uid: "can",
        isActive: false,
        unmatchedBy: "aya",
        alreadySubmitted: true,
      }),
      false,
    );
  });

  it("filters insults and PII", () => {
    const cleaned = sanitizeFeedback("salak call me at +905551112233 or a@b.com");
    assert.equal(cleaned.includes("salak"), false);
    assert.equal(cleaned.includes("a@b.com"), false);
    assert.equal(cleaned.includes("555"), false);
    assert.equal(cleaned.includes("***"), true);
  });
});

describe("message side effects payload", () => {
  // A nested-array arrayUnion once made the whole applyMessageSideEffects
  // transaction throw. lastMessage is written by the client, so the chat
  // looked fine while every server-side effect was silently lost: no unread
  // count, no isNewFor clear, no messagedUserIds entry, and the push that
  // runs after it never fired. Validate the real payload the way Firestore
  // validates a write, so the shape cannot regress.
  const {buildMessageSideEffectUpdates} = require("../lib/matchScore.js");
  const {Firestore} = require("@google-cloud/firestore");

  const payload = () =>
    buildMessageSideEffectUpdates({
      senderId: "aya",
      receiverId: "can",
      lastMessage: "\u{1F512}",
    });

  it("passes Firestore write validation", () => {
    // update() validates synchronously, before any RPC, so no emulator is
    // needed to prove the write would be accepted.
    const db = new Firestore({projectId: "validation-only"});
    const batch = db.batch();
    assert.doesNotThrow(() => {
      batch.update(db.doc("matches/aya_can"), payload());
    });
  });

  it("unions the sender id itself, never an array", () => {
    const union = payload().messagedUserIds;
    const elements = union._elements ?? union.elements;
    assert.ok(Array.isArray(elements), "arrayUnion should carry its elements");
    assert.deepEqual(elements, ["aya"]);
  });

  it("targets the receiver for unread and isNewFor", () => {
    const updates = payload();
    assert.ok("unreadCounts.can" in updates);
    assert.equal(updates["isNewFor.can"], false);
    assert.equal(updates.lastMessage, "\u{1F512}");
  });
});
