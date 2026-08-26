const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  isActiveForDiscovery,
  DISCOVERY_ACTIVE_DAYS,
  DISCOVERY_ACTIVE_MS,
} = require("../lib/discoveryActivity.js");

const now = Date.UTC(2026, 7, 20, 12);

describe("isActiveForDiscovery (90-day window)", () => {
  it("logged in today is visible", () => {
    assert.equal(isActiveForDiscovery(new Date(now), now), true);
  });

  it("1 month ago is visible", () => {
    assert.equal(isActiveForDiscovery(new Date(now - 30 * 86400000), now), true);
  });

  it("2 months 29 days is visible", () => {
    assert.equal(isActiveForDiscovery(new Date(now - 89 * 86400000), now), true);
  });

  it("more than 3 months is hidden", () => {
    assert.equal(isActiveForDiscovery(new Date(now - 91 * 86400000), now), false);
  });

  it("inactive user who logs in again becomes visible", () => {
    assert.equal(isActiveForDiscovery(new Date(now - 120 * 86400000), now), false);
    assert.equal(isActiveForDiscovery(new Date(now), now), true);
  });

  it("missing lastActiveAt (new user) is visible", () => {
    assert.equal(isActiveForDiscovery(null, now), true);
    assert.equal(isActiveForDiscovery(undefined, now), true);
  });

  it("uses a 90-day window", () => {
    assert.equal(DISCOVERY_ACTIVE_DAYS, 90);
    assert.equal(DISCOVERY_ACTIVE_MS, 90 * 24 * 60 * 60 * 1000);
  });
});
