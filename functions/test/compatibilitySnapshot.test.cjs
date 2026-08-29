const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildCompatibilitySnapshotFromProfiles,
} = require("../lib/compatibility/compatibilitySnapshot.js");
const {shapeIncomingLikesResponse} = require("../lib/incomingLikesShape.js");

test("buildCompatibilitySnapshotFromProfiles uses calculateCompatibility shape", () => {
  const snap = buildCompatibilitySnapshotFromProfiles({
    viewerProfile: {
      interests: ["travel", "music"],
      relationshipGoal: "longTerm",
      lifestyle: ["pets:dog"],
    },
    candidateProfile: {
      interests: ["travel", "design"],
      relationshipGoal: "longTerm",
      lifestyle: ["pets:dog"],
    },
    relationship: {
      score: 100,
      alignedCount: 3,
      sharedQuestionCount: 3,
      topTopics: ["communication"],
    },
    musicScore: 80,
  });
  assert.equal(typeof snap.compatibilityScore, "number");
  assert.ok(snap.compatibilityScore > 0);
  assert.equal(snap.compatibilityBreakdown.overallScore, snap.compatibilityScore);
  assert.equal(snap.compatibilityBreakdown.relationshipScore, 100);
  assert.equal(snap.compatibilityBreakdown.musicScore, 80);
  assert.ok(Array.isArray(snap.sharedInterests));
  assert.ok(Array.isArray(snap.compatibilityReasons));
});

test("buildCompatibilitySnapshotFromProfiles does not invent score without profiles", () => {
  const snap = buildCompatibilitySnapshotFromProfiles({
    viewerProfile: {},
    candidateProfile: {},
    relationship: null,
    musicScore: null,
  });
  assert.equal(typeof snap.compatibilityScore, "number");
  assert.ok(snap.compatibilityScore >= 0);
  assert.ok(snap.compatibilityScore <= 100);
});

test("incoming likes shape preserves optional compatibility fields", () => {
  const profiles = new Map([
    [
      "u2",
      {
        uid: "u2",
        displayName: "Ada",
        age: 28,
        photoUrl: null,
        city: "Istanbul",
        action: "like",
        createdAtMs: 1,
        compatibilityScore: 88,
        compatibilityBreakdown: {
          overallScore: 88,
          relationshipScore: 100,
          interestScore: 70,
          lifestyleScore: 80,
          questionScore: null,
          musicScore: null,
          communicationScore: null,
        },
        sharedInterests: ["travel"],
        compatibilityReasons: ["Shared interests"],
      },
    ],
  ]);
  const payload = shapeIncomingLikesResponse({
    isPremium: true,
    rows: [{fromUserId: "u2", action: "like", createdAtMs: 1}],
    profiles,
  });
  assert.equal(payload.items.length, 1);
  assert.equal(payload.items[0].compatibilityScore, 88);
  assert.equal(payload.items[0].compatibilityBreakdown.overallScore, 88);
});

test("free incoming likes never leak compatibility identities", () => {
  const profiles = new Map([
    [
      "u2",
      {
        uid: "u2",
        displayName: "Ada",
        age: 28,
        photoUrl: null,
        city: null,
        action: "like",
        createdAtMs: 1,
        compatibilityScore: 99,
      },
    ],
  ]);
  const payload = shapeIncomingLikesResponse({
    isPremium: false,
    rows: [{fromUserId: "u2", action: "like", createdAtMs: 1}],
    profiles,
  });
  assert.equal(payload.locked, true);
  assert.equal(payload.items.length, 0);
  assert.equal(payload.count, 1);
});
