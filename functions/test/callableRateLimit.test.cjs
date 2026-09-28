const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  rateLimitDecision,
  RATE_LIMIT_MAX,
  RATE_LIMIT_WINDOW_MS,
} = require("../lib/callableRateLimit.js");

describe("the budget in front of Spotify's token endpoint", () => {
  const now = 1_000_000;

  it("opens a window for a caller that has none", () => {
    assert.deepEqual(rateLimitDecision(null, now), {
      action: "start",
      count: 1,
      windowStart: now,
    });
  });

  it("counts within the window", () => {
    const decision = rateLimitDecision(
      {windowStart: now - 1000, count: 3},
      now,
    );
    assert.equal(decision.action, "increment");
    assert.equal(decision.count, 4);
    assert.equal(decision.windowStart, now - 1000);
  });

  it("refuses once the budget is spent", () => {
    const decision = rateLimitDecision(
      {windowStart: now - 1000, count: RATE_LIMIT_MAX},
      now,
    );
    assert.equal(decision.action, "refuse");
  });

  it("lets the last unit through", () => {
    const decision = rateLimitDecision(
      {windowStart: now - 1000, count: RATE_LIMIT_MAX - 1},
      now,
    );
    assert.equal(decision.action, "increment");
    assert.equal(decision.count, RATE_LIMIT_MAX);
  });

  it("starts fresh once the window has passed", () => {
    const decision = rateLimitDecision(
      {windowStart: now - RATE_LIMIT_WINDOW_MS - 1, count: RATE_LIMIT_MAX},
      now,
    );
    assert.equal(decision.action, "start");
    assert.equal(decision.count, 1);
  });

  it("does not expire a window that is exactly full-length", () => {
    const decision = rateLimitDecision(
      {windowStart: now - RATE_LIMIT_WINDOW_MS, count: 2},
      now,
    );
    assert.equal(decision.action, "increment");
  });

  it("treats a corrupt counter as a fresh window rather than a free pass", () => {
    const decision = rateLimitDecision(
      {windowStart: "yesterday", count: "lots"},
      now,
    );
    assert.equal(decision.action, "start");
    assert.equal(decision.count, 1);
    assert.equal(decision.windowStart, now);
  });
});
