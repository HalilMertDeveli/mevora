const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  buildCompatibilityReveal,
  collectRevealPoints,
} = require("../lib/compatibilityRevealEngine.js");

function baseInput(overrides = {}) {
  return {
    overallScore: 94,
    isPremium: false,
    sharedInterests: ["coffee", "hiking"],
    sameRelationshipGoal: true,
    relationshipGoalLabel: "longTerm",
    questionAlignedCount: 2,
    questionSharedCount: 3,
    questionScore: 67,
    questionTopTopics: ["personality", "communication"],
    musicScore: 88,
    lifestyleScore: 80,
    communicationScore: 80,
    breakdown: {
      relationshipScore: 100,
      interestScore: 70,
      lifestyleScore: 80,
      questionScore: 67,
      musicScore: 88,
      communicationScore: 80,
    },
    ...overrides,
  };
}

describe("compatibility reveal engine", () => {
  it("never invents music when musicScore is null", () => {
    const points = collectRevealPoints(
      baseInput({musicScore: null, breakdown: {...baseInput().breakdown, musicScore: null}}),
    );
    assert.equal(points.some((p) => p.kind === "music"), false);
  });

  it("never invents questions when no shared answers", () => {
    const points = collectRevealPoints(
      baseInput({
        questionAlignedCount: 0,
        questionSharedCount: 0,
        questionScore: null,
        questionTopTopics: [],
      }),
    );
    assert.equal(points.some((p) => p.kind === "questions"), false);
    assert.equal(points.some((p) => p.kind === "personality" && p.messageKey === "compatRevealPersonalityAligned"), false);
  });

  it("free users get at most 2 points and no breakdown", () => {
    const result = buildCompatibilityReveal(baseInput({isPremium: false}));
    assert.equal(result.available, true);
    assert.equal(result.overallScore, 94);
    assert.equal(result.points.length, 2);
    assert.equal(result.breakdown, null);
    assert.equal(result.premiumRequired, true);
  });

  it("premium users get up to 3 points and breakdown", () => {
    const result = buildCompatibilityReveal(baseInput({isPremium: true}));
    assert.equal(result.available, true);
    assert.equal(result.points.length, 3);
    assert.ok(result.breakdown);
    assert.equal(result.breakdown.musicScore, 88);
    assert.equal(result.premiumRequired, false);
  });

  it("returns unavailable when there are no real overlaps", () => {
    const result = buildCompatibilityReveal(
      baseInput({
        overallScore: 40,
        sharedInterests: [],
        sameRelationshipGoal: false,
        relationshipGoalLabel: null,
        questionAlignedCount: null,
        questionSharedCount: null,
        questionScore: null,
        questionTopTopics: [],
        musicScore: null,
        lifestyleScore: 40,
        communicationScore: null,
      }),
    );
    assert.equal(result.available, false);
    assert.deepEqual(result.points, []);
    assert.equal(result.reason, "insufficient_data");
  });

  it("includes personality only from verified topic or strong lifestyle", () => {
    const withTopic = collectRevealPoints(baseInput());
    assert.ok(withTopic.some((p) => p.kind === "personality"));

    const lifestyleOnly = collectRevealPoints(
      baseInput({
        questionAlignedCount: null,
        questionSharedCount: null,
        questionScore: null,
        questionTopTopics: [],
        lifestyleScore: 75,
      }),
    );
    assert.ok(
      lifestyleOnly.some(
        (p) => p.kind === "personality" && p.messageKey === "compatRevealSimilarPersonality",
      ),
    );
  });
});
