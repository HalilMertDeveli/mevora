const test = require("node:test");
const assert = require("node:assert/strict");
const {
  calculateCompatibility,
  legacyCompatibilityScore,
} = require("../lib/compatibility/compatibilityEngine.js");

test("calculateCompatibility uses viewer profile interests and goals", () => {
  const viewer = {
    interests: ["travel", "music"],
    relationshipGoal: "longTerm",
    lifestyle: ["pets:dog"],
  };
  const candidate = {
    interests: ["travel", "design"],
    relationshipGoal: "longTerm",
    lifestyle: ["pets:dog"],
  };
  const result = calculateCompatibility({
    viewerProfile: viewer,
    candidateProfile: candidate,
    relationship: {score: 100, alignedCount: 3, sharedQuestionCount: 3, topTopics: ["communication"]},
    musicScore: 80,
  });
  assert.ok(result.overallScore >= 70);
  assert.equal(result.relationshipScore, 100);
  assert.ok(result.sharedInterests.includes("travel"));
  assert.equal(result.questionScore, 100);
  assert.equal(result.musicScore, 80);
});

test("legacy score remains capped at 45", () => {
  const viewer = {interests: ["a", "b", "c", "d", "e", "f"], relationshipGoal: "longTerm"};
  const candidate = {interests: ["a", "b", "c", "d", "e", "f"], relationshipGoal: "longTerm"};
  const legacy = legacyCompatibilityScore(viewer, candidate);
  assert.equal(legacy.score, 45);
});
