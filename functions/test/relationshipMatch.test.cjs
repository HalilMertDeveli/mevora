const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  isValidRelationshipAnswer,
  scoreRelationshipCompatibility,
  answersFromSummary,
  canonicalCompatibilityKey,
  hashCompatibilityKey,
  setIdFor,
  isExactTriple,
  MAX_RELATIONSHIP_MATCH_KM,
  isWithinRelationshipRadius,
} = require("../lib/relationshipCompatibility.js");

describe("relationship compatibility", () => {
  it("rejects unknown question or answer ids", () => {
    assert.equal(isValidRelationshipAnswer("rq_001", "a"), true);
    assert.equal(isValidRelationshipAnswer("rq_110", "c"), true);
    assert.equal(isValidRelationshipAnswer("rq_111", "a"), true);
    assert.equal(isValidRelationshipAnswer("rq_000", "a"), false);
    assert.equal(isValidRelationshipAnswer("rq_112", "a"), false);
    assert.equal(isValidRelationshipAnswer("rq_001", "d"), false);
  });

  it("scores aligned answers over shared questions", () => {
    const result = scoreRelationshipCompatibility(
      {rq_001: "a", rq_002: "b", rq_005: "a"},
      {rq_001: "a", rq_002: "b", rq_007: "c"},
    );
    assert.equal(result.sharedQuestionCount, 2);
    assert.equal(result.alignedCount, 2);
    assert.equal(result.score, 100);
    assert.ok(result.topTopics.length >= 1);
  });

  it("does not treat different answers as a match signal", () => {
    const result = scoreRelationshipCompatibility(
      {rq_001: "a", rq_002: "b"},
      {rq_001: "b", rq_002: "a"},
    );
    assert.equal(result.alignedCount, 0);
    assert.equal(result.score, 0);
    assert.equal(result.sharedQuestionCount, 2);
  });

  it("never returns raw answers from a summary parser", () => {
    const parsed = answersFromSummary({
      answers: {rq_001: "a", bad: "z"},
      extra: "secret",
    });
    assert.deepEqual(parsed, {rq_001: "a"});
  });

  it("builds a sorted exact-match key from question and answer ids", () => {
    const key = canonicalCompatibilityKey(
      {rq_003: "c", rq_001: "a", rq_002: "b"},
      ["rq_003", "rq_001", "rq_002"],
    );
    assert.equal(key, "rq_001:a|rq_002:b|rq_003:c");
    assert.equal(setIdFor(["rq_001", "rq_002", "rq_003"]), "set_00");
    assert.equal(hashCompatibilityKey(key).length, 64);
    assert.equal(
      isExactTriple(
        {rq_001: "a", rq_002: "b", rq_003: "c"},
        {rq_001: "a", rq_002: "b", rq_003: "c"},
        ["rq_001", "rq_002", "rq_003"],
      ),
      true,
    );
    assert.equal(
      isExactTriple(
        {rq_001: "a", rq_002: "b", rq_003: "c"},
        {rq_001: "a", rq_002: "b", rq_003: "a"},
        ["rq_001", "rq_002", "rq_003"],
      ),
      false,
    );
  });

  it("caps automatic matches at 100 km and prefers a finite distance", () => {
    assert.equal(MAX_RELATIONSHIP_MATCH_KM, 100);
    assert.equal(isWithinRelationshipRadius(1.5), true);
    assert.equal(isWithinRelationshipRadius(100), true);
    assert.equal(isWithinRelationshipRadius(120), false);
    assert.equal(isWithinRelationshipRadius(null), false);
  });
});
