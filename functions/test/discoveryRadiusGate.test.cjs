const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  DISCOVERY_MAX_RADIUS_KM,
  isWithinDiscoveryRadius,
  resolveDiscoveryRadiusKm,
} = require("../lib/discoveryFallback.js");
const {coarseDistanceKm} = require("../lib/geo/coarseDistance.js");
const {
  MAX_RELATIONSHIP_MATCH_KM,
} = require("../lib/relationshipCompatibility.js");

describe("discovery hard radius gate", () => {
  it("shares one ceiling with relationship matching", () => {
    assert.equal(DISCOVERY_MAX_RADIUS_KM, 100);
    assert.equal(DISCOVERY_MAX_RADIUS_KM, MAX_RELATIONSHIP_MATCH_KM);
  });

  it("passes a requested step through and clamps anything above the ceiling", () => {
    assert.equal(resolveDiscoveryRadiusKm(5), 5);
    assert.equal(resolveDiscoveryRadiusKm(25), 25);
    assert.equal(resolveDiscoveryRadiusKm(100), 100);
    assert.equal(resolveDiscoveryRadiusKm(101), 100);
    assert.equal(resolveDiscoveryRadiusKm(500), 100);
    assert.equal(resolveDiscoveryRadiusKm(12_300), 100);
  });

  it("falls back to the ceiling for a radius it cannot use", () => {
    // Never fall back to "unlimited": an unusable request must not be a wider
    // gate than a usable one.
    for (const bad of [0, -5, Number.NaN, Number.POSITIVE_INFINITY, null, undefined, "x", {}]) {
      assert.equal(
        resolveDiscoveryRadiusKm(bad),
        DISCOVERY_MAX_RADIUS_KM,
        `resolveDiscoveryRadiusKm(${JSON.stringify(bad)})`,
      );
    }
  });

  it("excludes a candidate past the gate", () => {
    assert.equal(isWithinDiscoveryRadius(137, 100), false);
    assert.equal(isWithinDiscoveryRadius(54, 50), false);
    assert.equal(isWithinDiscoveryRadius(26, 25), false);
    assert.equal(isWithinDiscoveryRadius(350, 100), false);
    assert.equal(isWithinDiscoveryRadius(12_300, 100), false);
  });

  it("keeps a candidate inside the gate, boundary included", () => {
    assert.equal(isWithinDiscoveryRadius(0, 25), true);
    assert.equal(isWithinDiscoveryRadius(24.9, 25), true);
    assert.equal(isWithinDiscoveryRadius(25, 25), true);
    assert.equal(isWithinDiscoveryRadius(100, 100), true);
  });

  it("treats an unknown distance as not verifiably in range", () => {
    // The caller decides what to do with these; the predicate only refuses to
    // assert proximity it cannot measure.
    assert.equal(isWithinDiscoveryRadius(null, 100), false);
    assert.equal(isWithinDiscoveryRadius(undefined, 100), false);
    assert.equal(isWithinDiscoveryRadius(Number.NaN, 100), false);
    assert.equal(isWithinDiscoveryRadius(Number.POSITIVE_INFINITY, 100), false);
  });

  it("is why the gate must read the exact haversine, not the disclosed bucket", () => {
    // This is the regression the gate exists to prevent. coarseDistanceKm
    // flattens everything at or beyond the disclosure cap to exactly 100, so a
    // gate fed the disclosed figure would wave through the far side of the
    // planet while looking correct in every log line.
    const buenosAiresKm = 12_300;
    assert.equal(coarseDistanceKm(buenosAiresKm), 100);
    assert.equal(isWithinDiscoveryRadius(coarseDistanceKm(buenosAiresKm), 100), true);
    assert.equal(isWithinDiscoveryRadius(buenosAiresKm, 100), false);

    // Same failure one rung down, where the 5 km banding is the leak.
    const justOverFifty = 54;
    assert.equal(coarseDistanceKm(justOverFifty), 50);
    assert.equal(isWithinDiscoveryRadius(coarseDistanceKm(justOverFifty), 50), true);
    assert.equal(isWithinDiscoveryRadius(justOverFifty, 50), false);
  });
});
