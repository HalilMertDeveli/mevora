const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  datingPreference,
  passesGenderPreferences,
  passesDiscoveryProfileFilters,
} = require("../lib/discoveryMatching.js");

describe("discovery matching filters", () => {
  it("uses preferredGender before profile interestedIn", () => {
    assert.equal(
      datingPreference({preferredGender: "women"}, {interestedIn: "men"}),
      "women",
    );
  });

  it("requires mutual gender preference compatibility", () => {
    assert.equal(
      passesGenderPreferences({
        viewerPrefs: {interestedIn: "women"},
        viewerProfile: {gender: "man"},
        candidatePrefs: {interestedIn: "men"},
        candidateProfile: {gender: "woman"},
      }),
      true,
    );
    assert.equal(
      passesGenderPreferences({
        viewerPrefs: {interestedIn: "women"},
        viewerProfile: {gender: "man"},
        candidatePrefs: {interestedIn: "women"},
        candidateProfile: {gender: "man"},
      }),
      false,
    );
  });

  it("rejects suspended, deleted, and incomplete discovery profiles", () => {
    const photos = [
      {moderationStatus: "approved"},
      {moderationStatus: "approved"},
      {moderationStatus: "approved"},
    ];
    const baseProfile = {
      isDiscoverable: true,
      profileCompleted: true,
      age: 25,
      photos,
    };

    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: {...baseProfile, age: 17},
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: {
          ...baseProfile,
          profileModerationStatus: "suspended",
        },
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: baseProfile,
        candidateAccount: {accountStatus: "deleted"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: {...baseProfile, isDiscoverable: false},
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
  });
});
