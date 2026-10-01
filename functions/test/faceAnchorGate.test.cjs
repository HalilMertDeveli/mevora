const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {faceAnchorSatisfied, isProfileDiscoverable} = require("../lib/profileSafety.js");
const {
  discoveryProfileRejectReason,
  profileOnlyRejectReason,
} = require("../lib/discoveryMatching.js");
const {
  BUDGET_WINDOW_MS,
  COOLDOWN_MS,
  MAX_ATTEMPTS_PER_WINDOW,
  MAX_REFUNDS_PER_WINDOW,
  PROCESSING_STALE_MS,
  PROVIDER_TIMEOUT_MS,
  SELFIE_MAX_AGE_MS,
  ATTEMPT_TTL_MS,
  SUBMIT_TIMEOUT_SECONDS,
  budgetDecision,
  isProcessingFresh,
  parseFaceAnchorState,
  parseSelfiePath,
  refundedCounters,
  selfiePath,
} = require("../lib/faceAnchor/faceAnchorRecord.js");

const photo = (id, over = {}) => ({id, moderationStatus: "approved", downloadUrl: `https://cdn/${id}.jpg`, ...over});

/** A complete, adult, discoverable profile with three approved photos. */
function profile(over = {}) {
  return {
    uid: "u1",
    isDiscoverable: true,
    profileCompleted: true,
    profileModerationStatus: "approved",
    age: 30,
    birthDate: "1996-01-01",
    gender: "female",
    photos: [
      photo("a", {order: 0, isPrimary: true}),
      photo("b", {order: 1, isPrimary: false}),
      photo("c", {order: 2, isPrimary: false}),
    ],
    ...over,
  };
}

const account = {accountStatus: "active"};
const reason = (data) => discoveryProfileRejectReason({
  candidateProfile: data,
  candidateAccount: account,
  minAge: 18,
  maxAge: 99,
});

describe("face anchor gate — members under the rule", () => {
  it("a verified primary anchor is discoverable", () => {
    const data = profile({faceAnchorRequired: true, faceAnchorPhotoIds: ["a"]});
    assert.equal(faceAnchorSatisfied(data), true);
    assert.equal(isProfileDiscoverable(data), true);
    assert.equal(reason(data), null);
  });

  it("no anchor: not discoverable, with its own reason label", () => {
    const data = profile({faceAnchorRequired: true, faceAnchorPhotoIds: []});
    assert.equal(isProfileDiscoverable(data), false);
    assert.equal(reason(data), "face_anchor_missing");
    assert.equal(profileOnlyRejectReason({
      viewerPrefs: {},
      viewerProfile: {},
      candidateProfile: data,
      minAge: 18,
      maxAge: 99,
    }), "face_anchor_missing");
  });

  it("a missing or malformed anchor list is no anchor", () => {
    for (const faceAnchorPhotoIds of [undefined, null, "a", {a: true}, [1, null], [""]]) {
      assert.equal(faceAnchorSatisfied(profile({faceAnchorRequired: true, faceAnchorPhotoIds})), false);
    }
  });

  it("an anchor that is not the primary photo does not count", () => {
    const data = profile({faceAnchorRequired: true, faceAnchorPhotoIds: ["b"]});
    assert.equal(isProfileDiscoverable(data), false);
  });

  it("a client-written faceAnchorVerified on a photo means nothing here", () => {
    const data = profile({
      faceAnchorRequired: true,
      faceAnchorPhotoIds: [],
      photos: [
        photo("a", {order: 0, isPrimary: true, faceAnchorVerified: true}),
        photo("b", {order: 1}),
        photo("c", {order: 2}),
      ],
    });
    assert.equal(isProfileDiscoverable(data), false);
  });

  it("an anchor whose photo is no longer approved does not count", () => {
    const data = profile({
      faceAnchorRequired: true,
      faceAnchorPhotoIds: ["a"],
      photos: [
        photo("a", {order: 0, isPrimary: true, moderationStatus: "manual_review"}),
        photo("b", {order: 1}),
        photo("c", {order: 2}),
        photo("d", {order: 3}),
      ],
    });
    assert.equal(isProfileDiscoverable(data), false);
  });
});

describe("face anchor gate — every reading of 'first photo' must be an anchor", () => {
  // Until the reconciling trigger has run, position, order and the flag are
  // whatever a client wrote. Each of these would put a non-anchor in front of
  // some reader.
  const base = {faceAnchorRequired: true, faceAnchorPhotoIds: ["a"]};

  it("anchor flagged primary but a non-anchor first in the array", () => {
    const data = profile({...base, photos: [
      photo("b", {order: 1, isPrimary: false}),
      photo("a", {order: 0, isPrimary: true}),
      photo("c", {order: 2, isPrimary: false}),
    ]});
    assert.equal(isProfileDiscoverable(data), false);
  });

  it("anchor first in the array but a non-anchor with the lowest order", () => {
    const data = profile({...base, photos: [
      photo("a", {order: 5, isPrimary: true}),
      photo("b", {order: 0, isPrimary: false}),
      photo("c", {order: 1, isPrimary: false}),
    ]});
    assert.equal(isProfileDiscoverable(data), false);
  });

  it("anchor first and lowest but a non-anchor also flagged primary", () => {
    const data = profile({...base, photos: [
      photo("a", {order: 0, isPrimary: true}),
      photo("b", {order: 1, isPrimary: true}),
      photo("c", {order: 2, isPrimary: false}),
    ]});
    assert.equal(isProfileDiscoverable(data), false);
  });

  it("a pending photo in front does not matter: other members never see it", () => {
    const data = profile({...base, photos: [
      photo("new", {order: 0, isPrimary: false, moderationStatus: "pending"}),
      photo("a", {order: 1, isPrimary: true}),
      photo("b", {order: 2}),
      photo("c", {order: 3}),
    ]});
    assert.equal(isProfileDiscoverable(data), true);
  });
});

describe("face anchor gate — members not under the rule", () => {
  it("a profile completed before Face Anchor is unaffected", () => {
    const data = profile();
    assert.equal(faceAnchorSatisfied(data), true);
    assert.equal(isProfileDiscoverable(data), true);
    assert.equal(reason(data), null);
  });

  it("only the exact boolean puts a profile under the rule", () => {
    for (const faceAnchorRequired of [undefined, null, false, "true", 1]) {
      assert.equal(faceAnchorSatisfied(profile({faceAnchorRequired})), true);
    }
  });

  it("the other gates still apply and keep their labels", () => {
    assert.equal(reason(profile({isDiscoverable: false})), "not_discoverable");
    assert.equal(reason(profile({profileModerationStatus: "manual_review"})), "profile_moderation_manual_review");
    assert.equal(
      reason(profile({faceAnchorRequired: true, faceAnchorPhotoIds: [], profileModerationStatus: "rejected"})),
      "profile_moderation_rejected",
    );
  });
});

describe("face anchor record — budget", () => {
  const state = (over = {}) => parseFaceAnchorState({status: "awaiting_selfie", attemptId: "a", photoId: "p", ...over});
  const NOW = 1_800_000_000_000;

  it("the first attempt opens a window", () => {
    assert.deepEqual(budgetDecision(state(), NOW), {allowed: true, windowStartedAtMs: NOW, attemptCount: 1, refundCount: 0});
  });

  it("counts within the window and refuses past the limit", () => {
    const within = state({windowStartedAtMs: NOW - 1000, attemptCount: 2, lastAttemptAtMs: NOW - COOLDOWN_MS});
    assert.equal(budgetDecision(within, NOW).attemptCount, 3);
    const full = state({windowStartedAtMs: NOW - 1000, attemptCount: MAX_ATTEMPTS_PER_WINDOW, lastAttemptAtMs: NOW - COOLDOWN_MS});
    const decision = budgetDecision(full, NOW);
    assert.equal(decision.allowed, false);
    assert.equal(decision.reason, "attempt_limit");
    assert.ok(decision.retryAfterSeconds > 0);
  });

  it("a new window resets the count and the refunds", () => {
    const old = state({windowStartedAtMs: NOW - BUDGET_WINDOW_MS, attemptCount: 5, refundCount: 2, lastAttemptAtMs: NOW - BUDGET_WINDOW_MS});
    assert.deepEqual(budgetDecision(old, NOW), {allowed: true, windowStartedAtMs: NOW, attemptCount: 1, refundCount: 0});
  });

  it("the cooldown is checked first", () => {
    const hot = state({windowStartedAtMs: NOW - 5000, attemptCount: 1, lastAttemptAtMs: NOW - 5000});
    assert.deepEqual(budgetDecision(hot, NOW), {allowed: false, reason: "cooldown", retryAfterSeconds: (COOLDOWN_MS - 5000) / 1000});
  });

  it("refunds are capped and never go below zero", () => {
    assert.deepEqual(refundedCounters(state({attemptCount: 3, refundCount: 0})), {attemptCount: 2, refundCount: 1});
    assert.deepEqual(
      refundedCounters(state({attemptCount: 3, refundCount: MAX_REFUNDS_PER_WINDOW})),
      {attemptCount: 3, refundCount: MAX_REFUNDS_PER_WINDOW},
    );
    assert.deepEqual(refundedCounters(state({attemptCount: 0})), {attemptCount: 0, refundCount: 0});
  });

  it("garbage in the document reads as an empty state, not as a budget", () => {
    const parsed = parseFaceAnchorState({status: "verified!", reason: "because", attemptCount: "9", expiresAtMs: NaN});
    assert.equal(parsed.status, "none");
    assert.equal(parsed.reason, null);
    assert.equal(parsed.attemptCount, 0);
    assert.equal(parseFaceAnchorState(undefined).status, "none");
  });
});

describe("face anchor record — one clock", () => {
  it("three provider calls fit in the callable, and the callable inside the stale threshold", () => {
    assert.ok(3 * PROVIDER_TIMEOUT_MS < SUBMIT_TIMEOUT_SECONDS * 1000);
    assert.ok(SUBMIT_TIMEOUT_SECONDS * 1000 < PROCESSING_STALE_MS);
  });

  it("a selfie in legitimate use is younger than the sweep's age limit", () => {
    assert.ok(ATTEMPT_TTL_MS + PROCESSING_STALE_MS < SELFIE_MAX_AGE_MS);
  });

  it("processing is fresh only inside the threshold", () => {
    const s = parseFaceAnchorState({status: "processing", processingStartedAtMs: 1000});
    assert.equal(isProcessingFresh(s, 1000 + PROCESSING_STALE_MS - 1), true);
    assert.equal(isProcessingFresh(s, 1000 + PROCESSING_STALE_MS), false);
    assert.equal(isProcessingFresh(parseFaceAnchorState({status: "awaiting_selfie"}), 1000), false);
  });
});

describe("face anchor record — selfie paths", () => {
  it("is outside every profile photo prefix", () => {
    const path = selfiePath("uid-1", "attempt-1");
    assert.equal(path, "face-anchor/pending/uid-1/attempt-1");
    assert.equal(path.startsWith("users/"), false);
  });

  it("round-trips, and rejects anything shaped differently", () => {
    assert.deepEqual(parseSelfiePath("face-anchor/pending/u/a"), {uid: "u", attemptId: "a"});
    for (const name of ["face-anchor/pending/u", "face-anchor/pending/u/a/b", "users/u/profile/photos/a.jpg", ""]) {
      assert.equal(parseSelfiePath(name), null);
    }
  });
});
