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

describe("onboarding names", () => {
  const {
    MAX_FIRST_NAME_LENGTH,
    MAX_LAST_NAME_LENGTH,
    personNameIssue,
    requireOnboardingNames,
  } = require("../lib/personName.js");

  function refusal(profile, account) {
    try {
      requireOnboardingNames(profile, account);
      return null;
    } catch (error) {
      return `${error.code}:${error.message}`;
    }
  }

  it("a new account without a surname cannot finish onboarding", () => {
    const profile = {displayName: "Halil"};
    for (const account of [undefined, {}, {lastName: ""}, {lastName: "   "}, {lastName: 7}]) {
      assert.equal(refusal(profile, account), "failed-precondition:last-name-required");
    }
    // A surname on the public profile does not count: it must be on the account.
    assert.equal(
      refusal({displayName: "Halil", lastName: "Develi"}, {}),
      "failed-precondition:last-name-required",
    );
  });

  it("a new account without a first name cannot finish onboarding", () => {
    for (const displayName of [undefined, null, "", "   ", 42]) {
      assert.equal(
        refusal({displayName}, {lastName: "Develi"}),
        "failed-precondition:first-name-required",
      );
    }
  });

  it("accepts Turkish and international names, trimmed", () => {
    const names = [
      "Çağrı", "Gökçe", "İpek", "Işıl", "Öykü", "Şule", "Ümit",
      "José", "Zoë", "O'Brien", "Jean-Luc", "Ayşe Nur", "de la Cruz",
      "Öztürk-Şahin", "Нина", "محمد", "美咲",
    ];
    for (const name of names) {
      assert.equal(refusal({displayName: name}, {lastName: name}), null, name);
      assert.equal(refusal({displayName: `  ${name} `}, {lastName: ` ${name}  `}), null, name);
    }
  });

  it("applies the same length caps as the app", () => {
    assert.equal(MAX_FIRST_NAME_LENGTH, 40);
    assert.equal(MAX_LAST_NAME_LENGTH, 50);
    assert.equal(personNameIssue("a".repeat(40), MAX_FIRST_NAME_LENGTH), null);
    assert.equal(personNameIssue("a".repeat(41), MAX_FIRST_NAME_LENGTH), "too-long");
    assert.equal(
      refusal({displayName: "a".repeat(41)}, {lastName: "Develi"}),
      "failed-precondition:first-name-too-long",
    );
    assert.equal(
      refusal({displayName: "Halil"}, {lastName: "a".repeat(51)}),
      "failed-precondition:last-name-too-long",
    );
  });

  it("a name with no letter in it counts as missing", () => {
    for (const value of ["-", "'", "123", "...", "🙂"]) {
      assert.equal(personNameIssue(value, MAX_LAST_NAME_LENGTH), "required", value);
    }
  });

  it("a refusal names the field, never the name", () => {
    const longSurname = `Develi${"x".repeat(60)}`;
    const message = refusal({displayName: "Halil"}, {lastName: longSurname});
    assert.equal(message.includes("Develi"), false);
    assert.equal(message.includes("Halil"), false);
  });

  it("the public projection never carries a surname", () => {
    const projection = publicProfileProjection({
      ...adultProfile(),
      uid: "u1",
      displayName: "Halil",
      // Hostile or mistaken extra fields on the profile document.
      lastName: "Develi",
      firstName: "Halil",
      surname: "Develi",
      familyName: "Develi",
    });
    assert.equal(projection.displayName, "Halil");
    for (const key of ["lastName", "firstName", "surname", "familyName"]) {
      assert.equal(key in projection, false, key);
    }
    assert.equal(JSON.stringify(projection).includes("Develi"), false);
  });
});
