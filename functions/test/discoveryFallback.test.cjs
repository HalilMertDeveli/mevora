const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  classifyDiscoveryDistance,
  fillFromDistanceTiers,
  nextDiscoveryRadiusKm,
  DISCOVERY_EXTENDED_CAP_KM,
} = require("../lib/discoveryFallback.js");

describe("discovery fallback tiers", () => {
  it("classifies nearby / extended / far / no_location", () => {
    assert.equal(classifyDiscoveryDistance(5, 25, false, 25), "nearby");
    assert.equal(classifyDiscoveryDistance(80, 25, false, 25), "extended");
    assert.equal(classifyDiscoveryDistance(200, 25, false, 25), "far");
    assert.equal(classifyDiscoveryDistance(null, 25, false, 25), "no_location");
    assert.equal(DISCOVERY_EXTENDED_CAP_KM, 100);
  });

  it("fills nearby before no-location", () => {
    const {items, fallbackLevel} = fillFromDistanceTiers(
      {
        nearby: ["a"],
        extended: ["b"],
        far: ["c"],
        no_location: ["d"],
      },
      3,
    );
    assert.deepEqual(items, ["a", "b", "c"]);
    assert.equal(fallbackLevel, "far");
  });

  it("returns empty when no candidates", () => {
    const {items, fallbackLevel} = fillFromDistanceTiers(
      {nearby: [], extended: [], far: [], no_location: []},
      10,
    );
    assert.deepEqual(items, []);
    assert.equal(fallbackLevel, "empty");
  });

  it("escalates radius ladder", () => {
    assert.equal(nextDiscoveryRadiusKm(25), 50);
    assert.equal(nextDiscoveryRadiusKm(100), null);
  });
});
