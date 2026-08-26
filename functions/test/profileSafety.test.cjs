const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {
  ageFromBirthDate,
  resolveProfileAge,
  isAdultProfile,
  isAccountEligible,
  isProfileDiscoverable,
  publicProfileProjection,
  MIN_ONBOARDING_AGE,
} = require("../lib/profileSafety.js");
const {passesDiscoveryProfileFilters} = require("../lib/discoveryMatching.js");

function birthYearsAgo(years) {
  const today = new Date();
  return new Date(today.getFullYear() - years, today.getMonth(), today.getDate());
}

function adultProfile(overrides = {}) {
  const photos = Array.from({length: 3}, (_, index) => ({
    id: String(index),
    moderationStatus: "approved",
  }));
  return {
    isDiscoverable: true,
    profileCompleted: true,
    birthDate: Timestamp.fromDate(birthYearsAgo(25)),
    photos,
    ...overrides,
  };
}

describe("profile safety age gate", () => {
  it("treats 17 as underage and 18/19 as adult", () => {
    assert.equal(ageFromBirthDate(birthYearsAgo(17)), 17);
    assert.equal(ageFromBirthDate(birthYearsAgo(18)), 18);
    assert.equal(ageFromBirthDate(birthYearsAgo(19)), 19);
    assert.equal(isAdultProfile({birthDate: Timestamp.fromDate(birthYearsAgo(17))}), false);
    assert.equal(isAdultProfile({birthDate: Timestamp.fromDate(birthYearsAgo(18))}), true);
    assert.equal(isAdultProfile({birthDate: Timestamp.fromDate(birthYearsAgo(19))}), true);
    assert.equal(MIN_ONBOARDING_AGE, 18);
  });

  it("derives age from birthDate instead of spoofed age field", () => {
    const birthDate = birthYearsAgo(30);
    assert.equal(
      resolveProfileAge({
        birthDate: Timestamp.fromDate(birthDate),
        age: 99,
      }),
      ageFromBirthDate(birthDate),
    );
  });

  it("rejects profiles with missing age signals", () => {
    assert.equal(resolveProfileAge({}), null);
    assert.equal(resolveProfileAge({age: 0}), null);
    assert.equal(isAdultProfile({age: 17}), false);
  });
});

describe("account lifecycle for matching", () => {
  it("blocks banned, suspended, and deleted accounts", () => {
    assert.equal(isAccountEligible({isBanned: true}), false);
    assert.equal(isAccountEligible({accountStatus: "banned"}), false);
    assert.equal(isAccountEligible({accountStatus: "suspended"}), false);
    assert.equal(isAccountEligible({accountStatus: "deleted"}), false);
    assert.equal(isAccountEligible({accountStatus: "active"}), true);
  });

  it("filters suspended profiles out of discovery", () => {
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: adultProfile({profileModerationStatus: "suspended"}),
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: adultProfile({profileModerationStatus: "manual_review"}),
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
  });
});

describe("discoverability and public projection", () => {
  it("requires server discoverability flags and adult age", () => {
    assert.equal(isProfileDiscoverable(adultProfile()), true);
    assert.equal(isProfileDiscoverable(adultProfile({isDiscoverable: false})), false);
    assert.equal(
      isProfileDiscoverable(
        adultProfile({birthDate: Timestamp.fromDate(birthYearsAgo(17))}),
      ),
      false,
    );
  });

  it("requires three approved photos for discovery filters", () => {
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: adultProfile(),
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      true,
    );
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: adultProfile({
          photos: [{moderationStatus: "approved"}, {moderationStatus: "approved"}],
        }),
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
    assert.equal(
      passesDiscoveryProfileFilters({
        candidateProfile: adultProfile({
          photos: [
            {moderationStatus: "pending", downloadUrl: "https://a"},
            {moderationStatus: "pending", downloadUrl: "https://b"},
            {moderationStatus: "pending", downloadUrl: "https://c"},
          ],
        }),
        candidateAccount: {accountStatus: "active"},
        minAge: 18,
        maxAge: 99,
      }),
      false,
    );
  });

  it("public projection hides birthDate and pending photos", () => {
    const projection = publicProfileProjection({
      ...adultProfile(),
      uid: "u1",
      birthDate: Timestamp.fromDate(birthYearsAgo(24)),
      photos: [
        {id: "1", moderationStatus: "approved", downloadUrl: "a"},
        {id: "2", moderationStatus: "pending", downloadUrl: "b"},
      ],
    });
    assert.equal(projection.photos.length, 1);
    assert.equal("birthDate" in projection, false);
  });

  it("discovery projection excludes pending photos", () => {
    const {discoveryProfileProjection} = require("../lib/profileSafety.js");
    const projection = discoveryProfileProjection({
      ...adultProfile(),
      uid: "u1",
      photos: [
        {id: "1", moderationStatus: "approved", downloadUrl: "a"},
        {id: "2", moderationStatus: "pending", downloadUrl: "b"},
        {id: "3", moderationStatus: "rejected", downloadUrl: "c"},
      ],
    });
    assert.equal(projection.photos.length, 1);
  });
});
