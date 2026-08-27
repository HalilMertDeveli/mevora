const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const ranking = require(path.join(__dirname, "..", "lib", "boost", "ranking.js"));
const catalog = require(path.join(__dirname, "..", "lib", "boost", "catalog.js"));
const config = require(path.join(__dirname, "..", "lib", "boost", "config.js"));
const quality = require(
  path.join(__dirname, "..", "lib", "boost", "profileQuality.js"),
);

test("smart boost packs: 30m / 1h / 24h are duration packs", () => {
  const starter = catalog.defaultPackFor(config.BOOST_PRODUCT_IDS.starter30m);
  const popular = catalog.defaultPackFor(config.BOOST_PRODUCT_IDS.popular1h);
  const power = catalog.defaultPackFor(config.BOOST_PRODUCT_IDS.power24h);
  assert.ok(starter && catalog.isDurationPack(starter));
  assert.ok(popular && catalog.isDurationPack(popular));
  assert.ok(power && catalog.isDurationPack(power));
  assert.equal(starter.durationMs, 30 * 60 * 1000);
  assert.equal(popular.durationMs, 60 * 60 * 1000);
  assert.equal(power.durationMs, 24 * 60 * 60 * 1000);
  assert.equal(starter.boostType, "smart");
});

test("ranking: high compatibility beats boosted low compatibility", () => {
  const boosted = new Set(["low"]);
  const high = {
    uid: "high",
    compatibilityScore: 95,
    musicRankingBonus: 0,
    distanceKm: 10,
    relationshipAlignedCount: 0,
  };
  const low = {
    uid: "low",
    compatibilityScore: 60,
    musicRankingBonus: 0,
    distanceKm: 10,
    relationshipAlignedCount: 0,
  };
  const highScore = ranking.computeDiscoveryRankScore(high, boosted, 25);
  const lowScore = ranking.computeDiscoveryRankScore(low, boosted, 25);
  assert.ok(highScore > lowScore);
});

test("ranking: boost can lift near-equal compatibility", () => {
  const boosted = new Set(["b"]);
  const a = {
    uid: "a",
    compatibilityScore: 90,
    musicRankingBonus: 0,
    distanceKm: 10,
  };
  const b = {
    uid: "b",
    compatibilityScore: 88,
    musicRankingBonus: 0,
    distanceKm: 10,
  };
  const aScore = ranking.computeDiscoveryRankScore(a, boosted, 25);
  const bScore = ranking.computeDiscoveryRankScore(b, boosted, 25);
  assert.ok(bScore > aScore);
});

test("ranking: question tier still beats boost", () => {
  const boosted = new Set(["b"]);
  const a = {
    uid: "a",
    compatibilityScore: 50,
    relationshipAlignedCount: 3,
    distanceKm: 10,
    musicRankingBonus: 0,
  };
  const b = {
    uid: "b",
    compatibilityScore: 99,
    relationshipAlignedCount: 0,
    distanceKm: 5,
    musicRankingBonus: 0,
  };
  const sorted = ranking.sortByBoostVisibility([b, a], boosted, 25);
  assert.equal(sorted[0].uid, "a");
});

test("profile quality: spotify optional bonus only", () => {
  const without = quality.computeProfileQuality({
    photoCount: 3,
    hasBio: true,
    hasAge: true,
    hasLocation: true,
    hasRelationshipGoal: true,
    personalityAnswerCount: 3,
    profileCompleted: true,
    spotifyConnected: false,
    hoursSinceActive: 1,
  });
  const withSpotify = quality.computeProfileQuality({
    photoCount: 3,
    hasBio: true,
    hasAge: true,
    hasLocation: true,
    hasRelationshipGoal: true,
    personalityAnswerCount: 3,
    profileCompleted: true,
    spotifyConnected: true,
    hoursSinceActive: 1,
  });
  assert.ok(without.score >= 70);
  assert.ok(withSpotify.score >= without.score);
});
