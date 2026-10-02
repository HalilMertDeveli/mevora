const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  MAX_MESSAGES_GLOBAL,
  MAX_MESSAGES_PER_MATCH,
  MESSAGE_RATE_WINDOW_MS,
  messageRateDecision,
  parseMessageRateState,
} = require("../lib/messageRateLimitPolicy.js");

const now = 10_000_000;

function empty() {
  return parseMessageRateState(undefined, 0);
}

/** Sends `n` messages into `matchId`, returning the state after the last. */
function sendMany(state, matchId, n, at = now) {
  let current = state;
  for (let i = 0; i < n; i++) {
    const decision = messageRateDecision(current, {
      matchId,
      messageId: `${matchId}-${current.count}-${i}`,
      nowMs: at,
    });
    assert.equal(decision.action, "accept");
    current = decision.state;
  }
  return current;
}

describe("message rate limit from the sender's counter", () => {
  it("opens a window on the first message", () => {
    const decision = messageRateDecision(empty(), {matchId: "a_b", messageId: "m1", nowMs: now});
    assert.equal(decision.action, "accept");
    assert.deepEqual(decision.state, {
      windowStartMs: now,
      count: 1,
      perMatch: {a_b: 1},
      messageIds: ["m1"],
    });
  });

  it("blocks the 21st message in one match within the window", () => {
    const state = sendMany(empty(), "a_b", MAX_MESSAGES_PER_MATCH);
    const decision = messageRateDecision(state, {matchId: "a_b", messageId: "extra", nowMs: now + 1000});
    assert.deepEqual(decision, {action: "reject", reason: "match"});
  });

  it("still allows other matches when one match is full", () => {
    const state = sendMany(empty(), "a_b", MAX_MESSAGES_PER_MATCH);
    const decision = messageRateDecision(state, {matchId: "a_c", messageId: "other", nowMs: now});
    assert.equal(decision.action, "accept");
  });

  it("blocks the 61st message across matches", () => {
    let state = empty();
    state = sendMany(state, "a_b", 20);
    state = sendMany(state, "a_c", 20);
    state = sendMany(state, "a_d", 20);
    assert.equal(state.count, MAX_MESSAGES_GLOBAL);
    const decision = messageRateDecision(state, {matchId: "a_e", messageId: "x", nowMs: now});
    assert.deepEqual(decision, {action: "reject", reason: "global"});
  });

  it("starts a fresh window, per-match counts included, after 60 s", () => {
    const state = sendMany(empty(), "a_b", MAX_MESSAGES_PER_MATCH);
    const later = now + MESSAGE_RATE_WINDOW_MS + 1;
    const decision = messageRateDecision(state, {matchId: "a_b", messageId: "next", nowMs: later});
    assert.equal(decision.action, "accept");
    assert.deepEqual(decision.state, {
      windowStartMs: later,
      count: 1,
      perMatch: {a_b: 1},
      messageIds: ["next"],
    });
  });

  it("counts a redelivered trigger for the same message once", () => {
    const first = messageRateDecision(empty(), {matchId: "a_b", messageId: "m1", nowMs: now});
    const again = messageRateDecision(first.state, {matchId: "a_b", messageId: "m1", nowMs: now + 5});
    assert.deepEqual(again, {action: "duplicate"});
  });

  it("does not count a rejected message", () => {
    const state = sendMany(empty(), "a_b", MAX_MESSAGES_PER_MATCH);
    messageRateDecision(state, {matchId: "a_b", messageId: "extra", nowMs: now});
    assert.equal(state.count, MAX_MESSAGES_PER_MATCH);
  });

  it("treats a malformed counter document as an empty window", () => {
    const state = parseMessageRateState(
      {count: "lots", perMatch: {a_b: "x", a_c: -2, a_d: 3}, messageIds: "nope"},
      now,
    );
    assert.deepEqual(state, {windowStartMs: now, count: 0, perMatch: {a_d: 3}, messageIds: []});
  });

  it("reads a legacy counter written before per-match counts existed", () => {
    const state = parseMessageRateState({count: 7}, now);
    const decision = messageRateDecision(state, {matchId: "a_b", messageId: "m", nowMs: now + 10});
    assert.equal(decision.action, "accept");
    assert.equal(decision.state.count, 8);
    assert.deepEqual(decision.state.perMatch, {a_b: 1});
  });
});
