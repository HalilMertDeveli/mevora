const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  questionAlignmentTier,
  compareDiscoveryCandidates,
  sortByBoostVisibility,
} = require("../lib/boost/ranking.js");
const {
  normalizeAnswerId,
  scoreRelationshipCompatibility,
} = require("../lib/relationshipCompatibility.js");

describe("question alignment ranking", () => {
  it("prioritizes 3/3 over closer 0/3 candidates", () => {
    const boosted = new Set();
    const exact = {
      uid: "far-exact",
      relationshipAlignedCount: 3,
      relationshipSharedViewCount: 3,
      distanceKm: 8,
      compatibilityScore: 70,
    };
    const near = {
      uid: "near-none",
      relationshipAlignedCount: 0,
      distanceKm: 0.1,
      compatibilityScore: 90,
    };
    assert.equal(questionAlignmentTier(exact), 3);
    assert.ok(compareDiscoveryCandidates(exact, near, boosted, 25) < 0);
    const sorted = sortByBoostVisibility([near, exact], boosted, 25);
    assert.equal(sorted[0].uid, "far-exact");
  });

  it("uses distance among equal 3/3 candidates", () => {
    const boosted = new Set();
    const closer = {
      uid: "close",
      relationshipAlignedCount: 3,
      distanceKm: 0.4,
      compatibilityScore: 80,
    };
    const farther = {
      uid: "far",
      relationshipAlignedCount: 3,
      distanceKm: 8,
      compatibilityScore: 95,
    };
    const sorted = sortByBoostVisibility([farther, closer], boosted, 25);
    assert.equal(sorted[0].uid, "close");
  });
});

describe("answer id normalization", () => {
  it("normalizes option_3 / 3 / C to c", () => {
    assert.equal(normalizeAnswerId("option_3"), "c");
    assert.equal(normalizeAnswerId("3"), "c");
    assert.equal(normalizeAnswerId("C"), "c");
    assert.equal(normalizeAnswerId("a"), "a");
  });

  it("scores matching answers after normalization", () => {
    const score = scoreRelationshipCompatibility(
      {rq_001: "a", rq_002: "b", rq_003: "c"},
      {rq_001: "A", rq_002: "option_b", rq_003: "3"},
    );
    assert.equal(score.alignedCount, 3);
    assert.equal(score.sharedQuestionCount, 3);
    assert.equal(score.score, 100);
  });
});
