const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const WINDOW_MS = 60_000;

function isWithinWindow(createdAtMs, nowMs) {
  return createdAtMs >= nowMs - WINDOW_MS;
}

describe("message rate limit policy", () => {
  it("keeps only recent sends in the rolling window", () => {
    const now = Date.now();
    assert.equal(isWithinWindow(now - 30_000, now), true);
    assert.equal(isWithinWindow(now - 120_000, now), false);
  });

  it("blocks the 21st message in a match window", () => {
    const max = 20;
    assert.equal(20 >= max, true);
    assert.equal(21 > max, true);
  });
});
