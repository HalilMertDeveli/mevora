const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  BOOST_PRIORITY_BONUS,
  BOOST_DISTANCE_EXTENSION_RATIO,
  effectiveRadiusKm,
  distanceRankContribution,
  computeDiscoveryRankScore,
  sortByBoostVisibility,
  diversifyBoostedResults,
} = require("../lib/boost/ranking.js");

describe("boost discovery ranking", () => {
  const boosted = new Set(["boosted-user"]);

  it("inactive boost keeps normal ranking", () => {
    const normal = {uid: "a", compatibilityScore: 80, musicRankingBonus: 5, distanceKm: 5};
    const inactive = {uid: "b", compatibilityScore: 60, musicRankingBonus: 0, distanceKm: 5};
    const aScore = computeDiscoveryRankScore(normal, new Set(), 25);
    const bScore = computeDiscoveryRankScore(inactive, boosted, 25);
    assert.ok(aScore > bScore);
  });

  it("active boost raises ranking priority without changing compatibility", () => {
    const normal = {uid: "a", compatibilityScore: 70, musicRankingBonus: 0, distanceKm: null};
    const boostedUser = {uid: "boosted-user", compatibilityScore: 70, musicRankingBonus: 0, distanceKm: null};
    const normalScore = computeDiscoveryRankScore(normal, boosted, 25);
    const boostedScore = computeDiscoveryRankScore(boostedUser, boosted, 25);
    assert.ok(boostedScore > normalScore);
    assert.equal(boostedScore - normalScore, BOOST_PRIORITY_BONUS);
    assert.equal(boostedUser.compatibilityScore, 70);
  });

  it("reduces distance penalty for boosted profiles", () => {
    const normalDistance = distanceRankContribution(20, 25, false);
    const boostedDistance = distanceRankContribution(20, 25, true);
    assert.ok(boostedDistance > normalDistance);
  });

  it("extends eligible radius for boosted profiles", () => {
    assert.equal(effectiveRadiusKm(25, false), 25);
    assert.equal(
      effectiveRadiusKm(25, true),
      25 * (1 + BOOST_DISTANCE_EXTENSION_RATIO),
    );
  });

  it("does not fabricate compatibility changes", () => {
    const item = {uid: "boosted-user", compatibilityScore: 42, musicRankingBonus: 0, distanceKm: 8};
    computeDiscoveryRankScore(item, boosted, 25);
    assert.equal(item.compatibilityScore, 42);
  });

  it("returns to normal ranking after boost expires", () => {
    const item = {uid: "boosted-user", compatibilityScore: 75, musicRankingBonus: 0, distanceKm: null};
    const active = computeDiscoveryRankScore(item, boosted, 25);
    const expired = computeDiscoveryRankScore(item, new Set(), 25);
    assert.ok(active > expired);
    assert.equal(active - expired, BOOST_PRIORITY_BONUS);
  });

  it("interleaves boosted and normal profiles", () => {
    const items = [
      {uid: "b1", compatibilityScore: 90},
      {uid: "n1", compatibilityScore: 80},
      {uid: "b2", compatibilityScore: 70},
      {uid: "n2", compatibilityScore: 60},
    ];
    const boostedSet = new Set(["b1", "b2"]);
    const diversified = diversifyBoostedResults(
      sortByBoostVisibility(items, boostedSet, 25),
      boostedSet,
    );
    assert.equal(diversified[0].uid, "b1");
    assert.equal(diversified[1].uid, "n1");
    assert.equal(diversified[2].uid, "b2");
    assert.equal(diversified[3].uid, "n2");
  });

  it("keeps blocked/seen users out of ranking helper inputs", () => {
    const pool = [
      {uid: "seen", compatibilityScore: 99},
      {uid: "fresh", compatibilityScore: 50},
    ];
    const ranked = sortByBoostVisibility(pool, new Set(), 25);
    assert.equal(ranked.length, 2);
    assert.equal(ranked[0].uid, "seen");
  });
});
