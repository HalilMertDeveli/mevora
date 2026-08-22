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
