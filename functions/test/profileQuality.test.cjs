const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  computeProfileQuality,
  profileQualityFromDocs,
  PROFILE_QUALITY_FLOOR,
  PROFILE_PHOTO_TARGET,
} = require("../lib/recommendation/profileQuality.js");
const {
  computeRecommendationScore,
} = require("../lib/recommendation/recommendationEngine.js");

describe("profile quality score", () => {
  it("awards full photos when 3+ photos are present", () => {
    const withThree = computeProfileQuality({
      photoCount: PROFILE_PHOTO_TARGET,
      hasBio: true,
      hasAge: true,
      hasLocation: true,
      hasRelationshipGoal: true,
      personalityAnswerCount: 3,
      profileCompleted: true,
      spotifyConnected: false,
      hoursSinceActive: 1,
    });
    const withTwo = computeProfileQuality({
      photoCount: 2,
      hasBio: true,
      hasAge: true,
      hasLocation: true,
      hasRelationshipGoal: true,
      personalityAnswerCount: 3,
      profileCompleted: true,
      spotifyConnected: false,
      hoursSinceActive: 1,
    });
    assert.equal(withThree.factors.photos, 25);
    assert.ok(withThree.score > withTwo.score);
    assert.ok(withThree.score >= 70);
    assert.ok(!withThree.suggestions.some((s) => s.includes("photos")));
    assert.ok(withTwo.suggestions.includes("add_1_photos"));
  });

  it("treats Spotify as optional bonus only", () => {
    const without = computeProfileQuality({
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
    const withSpotify = computeProfileQuality({
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
    assert.equal(without.factors.spotifyBonus, 0);
    assert.equal(withSpotify.factors.spotifyBonus, 5);
    assert.ok(withSpotify.score >= without.score);
    assert.ok(without.score <= 100);
    assert.ok(!without.suggestions.includes("optional_connect_spotify"));
  });

  it("floors sparse profiles instead of zeroing them", () => {
    const empty = computeProfileQuality({
      photoCount: 0,
      hasBio: false,
      hasAge: false,
      hasLocation: false,
      hasRelationshipGoal: false,
      personalityAnswerCount: 0,
      profileCompleted: false,
      spotifyConnected: false,
      hoursSinceActive: 9999,
    });
    assert.equal(empty.score, PROFILE_QUALITY_FLOOR);
    assert.ok(empty.suggestions.includes("add_bio"));
    assert.ok(empty.suggestions.includes("complete_personality_test"));
  });

  it("accepts city as location from profile docs", () => {
    const quality = profileQualityFromDocs({
      profile: {
        photos: [
          {id: "1", storagePath: "a.jpg", moderationStatus: "approved"},
          {id: "2", storagePath: "b.jpg", moderationStatus: "approved"},
          {id: "3", storagePath: "c.jpg", moderationStatus: "approved"},
        ],
        bio: "Hello there friend",
        age: 28,
        city: "Istanbul",
        relationshipGoal: "longTerm",
        profileCompleted: true,
      },
      user: {lastActiveAt: Date.now()},
      musicSummary: {spotifyConnected: false},
      personalityAnswerCount: 3,
      nowMs: Date.now(),
    });
    assert.equal(quality.factors.location, 10);
    assert.ok(quality.score >= 90);
  });

  it("never hard-excludes via recommendation signal floor", () => {
    const result = computeRecommendationScore({
      compatibilityScore: 0,
      preferenceScore: 0,
      activityScore: 0,
      profileQualityScore: 0,
      freshnessScore: 0,
      isBoosted: false,
    });
    assert.ok(result.baseScore > 0);
    assert.ok(result.signals.profileQuality >= 0.05);
  });
});
