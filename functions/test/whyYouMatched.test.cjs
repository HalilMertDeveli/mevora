const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildWhyYouMatchedReasons,
} = require("../lib/whyYouMatched/reasonBuilder.js");
const {
  compareHumorAnswers,
  humorAnswerConfidence,
  humorAnswerStrength,
  meetsHumorAnswerReasonThreshold,
  isHumorQuestionId,
} = require("../lib/whyYouMatched/humorAnswerComparison.js");
const {
  sanitizeForClient,
  containsForbiddenKey,
  pickRequestFields,
} = require("../lib/whyYouMatched/sanitize.js");

function baseInput(overrides = {}) {
  return {
    viewerUid: "a",
    peerUid: "b",
    viewerInterests: ["music", "travel"],
    peerInterests: ["music", "gaming"],
    viewerLanguages: ["en", "tr"],
    peerLanguages: ["en"],
    viewerLifestyleTags: ["smoking:no", "pets:yes"],
    peerLifestyleTags: ["smoking:no", "pets:yes"],
    musicScore: 88,
    sharedArtistNames: ["Daft Punk", "Radiohead"],
    sharedArtistCount: 3,
    sharedTrackCount: 0,
    sharedGenreNames: [],
    humorScore: 86,
    humorConfidence: 0.5,
    humorSharedDims: ["absurd"],
    humorMatchingAnswers: 4,
    humorComparableAnswers: 5,
    questionAlignedCount: 3,
    questionSharedCount: 4,
    communicationTopic: true,
    distanceKm: 4,
    overallScore: 82,
    ...overrides,
  };
}

test("integration: builds top reasons from real aggregates without inventing", () => {
  const reasons = buildWhyYouMatchedReasons(baseInput());
  assert.ok(reasons.length >= 1);
  assert.ok(reasons.length <= 3);
  const types = reasons.map((r) => r.evidence.type);
  assert.ok(types.includes("sharedHumorAnswers") || types.includes("commonArtists"));
  for (const r of reasons) {
    assert.ok(r.evidence.type);
    assert.ok(r.score >= 0 && r.score <= 100);
    assert.ok(!JSON.stringify(r).toLowerCase().includes("latitude"));
  }
});

test("integration: missing music/humor/location still allows interests", () => {
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      musicScore: null,
      humorScore: null,
      humorMatchingAnswers: null,
      humorComparableAnswers: null,
      distanceKm: null,
      communicationTopic: false,
      questionAlignedCount: null,
      questionSharedCount: null,
      viewerLifestyleTags: [],
      peerLifestyleTags: [],
      viewerLanguages: [],
      peerLanguages: [],
    }),
  );
  assert.equal(reasons.length, 1);
  assert.equal(reasons[0].evidence.type, "commonInterests");
});

test("integration: empty overlaps → no reasons", () => {
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      viewerInterests: [],
      peerInterests: [],
      musicScore: null,
      humorScore: null,
      humorMatchingAnswers: null,
      humorComparableAnswers: null,
      distanceKm: null,
      communicationTopic: false,
      questionAlignedCount: null,
      questionSharedCount: null,
      viewerLifestyleTags: [],
      peerLifestyleTags: [],
      viewerLanguages: [],
      peerLanguages: [],
    }),
  );
  assert.equal(reasons.length, 0);
});

test("security: sanitize strips coordinates and tokens", () => {
  const dirty = {
    available: true,
    latitude: 41.0,
    peer: {longitude: 29.0, displayName: "Ada"},
    evidence: {type: "x", lat: 1, count: 2},
    accessToken: "secret",
    reasons: [{id: "r1", score: 80}],
  };
  const clean = sanitizeForClient(dirty);
  assert.equal(clean.latitude, undefined);
  assert.equal(clean.accessToken, undefined);
  assert.equal(clean.peer.longitude, undefined);
  assert.equal(clean.peer.displayName, "Ada");
  assert.equal(clean.evidence.lat, undefined);
  assert.equal(clean.evidence.count, 2);
  assert.equal(clean.reasons[0].score, 80);
});

test("security: forbidden key detector", () => {
  assert.equal(containsForbiddenKey("latitude"), true);
  assert.equal(containsForbiddenKey("geohash"), true);
  assert.equal(containsForbiddenKey("count"), false);
});

test("security: request picker ignores client score injection fields", () => {
  const picked = pickRequestFields({
    matchId: "a_b",
    forceRefresh: true,
    overallScore: 100,
    reasons: [{fake: true}],
    musicScore: 99,
  });
  assert.deepEqual(picked, {matchId: "a_b", forceRefresh: true});
});

test("distance evidence never includes exact coordinates", () => {
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      viewerInterests: [],
      peerInterests: [],
      musicScore: null,
      humorMatchingAnswers: null,
      humorComparableAnswers: null,
      humorScore: null,
      communicationTopic: false,
      questionAlignedCount: null,
      viewerLifestyleTags: [],
      peerLifestyleTags: [],
      viewerLanguages: [],
      peerLanguages: [],
      distanceKm: 0.3,
    }),
  );
  assert.equal(reasons.length, 1);
  assert.equal(reasons[0].evidence.type, "proximityKm");
  const blob = JSON.stringify(reasons[0]);
  assert.equal(blob.includes("lat"), false);
  assert.equal(blob.includes("lng"), false);
});

test("humor Q&A: identical fun-category answers produce matching counts", () => {
  const viewer = {
    rq_002: "ra_002_a",
    rq_005: "ra_005_a",
    rq_008: "ra_008_a",
    rq_011: "ra_011_a",
    rq_014: "ra_014_a",
  };
  const candidate = {...viewer};
  const comparison = compareHumorAnswers(viewer, candidate);
  assert.equal(comparison.comparableAnswers, 5);
  assert.equal(comparison.matchingAnswers, 5);
  assert.equal(comparison.score, 100);
  assert.equal(meetsHumorAnswerReasonThreshold(comparison), true);
  assert.equal(humorAnswerStrength(comparison), "strong");
  assert.ok(humorAnswerConfidence(comparison) >= 0.35);
});

test("humor Q&A: insufficient comparable answers → no reason", () => {
  const viewer = {rq_002: "ra_002_a", rq_005: "ra_005_a"};
  const candidate = {rq_002: "ra_002_a", rq_005: "ra_005_b"};
  const comparison = compareHumorAnswers(viewer, candidate);
  assert.equal(comparison.comparableAnswers, 2);
  assert.equal(comparison.matchingAnswers, 1);
  assert.equal(comparison.score, 50);
  assert.equal(meetsHumorAnswerReasonThreshold(comparison), false);

  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      humorMatchingAnswers: comparison.matchingAnswers,
      humorComparableAnswers: comparison.comparableAnswers,
      humorScore: null,
    }),
  );
  const humorReasons = reasons.filter((r) => r.category === "humor");
  assert.equal(humorReasons.length, 0);
});

test("humor Q&A: non-humor questions are excluded from comparison", () => {
  const viewer = {
    rq_002: "ra_002_a",
    rq_999: "ra_999_a",
    unknown_q: "x",
  };
  const candidate = {
    rq_002: "ra_002_a",
    rq_999: "ra_999_b",
    unknown_q: "x",
  };
  const comparison = compareHumorAnswers(viewer, candidate);
  assert.equal(comparison.comparableAnswers, 1);
  assert.equal(comparison.matchingAnswers, 1);
  assert.equal(isHumorQuestionId("rq_002"), true);
  assert.equal(isHumorQuestionId("rq_999"), false);
});

test("humor Q&A: insufficient comparable with perfect score stays moderate not strong", () => {
  const comparison = compareHumorAnswers(
    {rq_002: "ra_002_a", rq_005: "ra_005_a"},
    {rq_002: "ra_002_a", rq_005: "ra_005_a"},
  );
  assert.equal(comparison.comparableAnswers, 2);
  assert.equal(comparison.matchingAnswers, 2);
  assert.equal(comparison.score, 100);
  assert.equal(meetsHumorAnswerReasonThreshold(comparison), true);
  assert.equal(humorAnswerStrength(comparison), "moderate");
});

test("humor Q&A: 4/5 match uses sharedHumorAnswers evidence with aligned confidence", () => {
  const matching = 4;
  const total = 5;
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      viewerInterests: [],
      peerInterests: [],
      musicScore: null,
      humorMatchingAnswers: matching,
      humorComparableAnswers: total,
      humorScore: null,
      viewerLifestyleTags: [],
      peerLifestyleTags: [],
      viewerLanguages: [],
      peerLanguages: [],
      communicationTopic: false,
      questionAlignedCount: null,
      questionSharedCount: null,
      distanceKm: null,
    }),
  );
  const humor = reasons.find((r) => r.category === "humor");
  assert.ok(humor);
  assert.equal(humor.evidence.type, "sharedHumorAnswers");
  assert.equal(humor.evidence.values.matching, matching);
  assert.equal(humor.evidence.values.comparable, total);
  assert.equal(humor.score, 80);
  const comparison = {
    comparableAnswers: total,
    matchingAnswers: matching,
    similarity: matching / total,
    score: 80,
  };
  assert.equal(humor.confidence, humorAnswerConfidence(comparison));
  assert.equal(humor.strength, humorAnswerStrength(comparison));
});

test("humor Q&A: prefers answers path over lab score when both available", () => {
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      viewerInterests: [],
      peerInterests: [],
      musicScore: null,
      humorMatchingAnswers: 4,
      humorComparableAnswers: 5,
      humorScore: 95,
      humorConfidence: 0.9,
      viewerLifestyleTags: [],
      peerLifestyleTags: [],
      viewerLanguages: [],
      peerLanguages: [],
      communicationTopic: false,
      questionAlignedCount: null,
      questionSharedCount: null,
      distanceKm: null,
    }),
  );
  const humor = reasons.filter((r) => r.category === "humor");
  assert.equal(humor.length, 1);
  assert.equal(humor[0].evidence.type, "sharedHumorAnswers");
});

test("humor Q&A: empty answers → no humor reason from Q&A path", () => {
  const comparison = compareHumorAnswers({}, {rq_002: "ra_002_a"});
  assert.equal(comparison.comparableAnswers, 0);
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      humorMatchingAnswers: null,
      humorComparableAnswers: null,
      humorScore: null,
    }),
  );
  const humor = reasons.filter((r) => r.category === "humor");
  assert.equal(humor.length, 0);
});

test("interests confidence uses count/3 clamped to [0.4, 1.0]", () => {
  const reasons = buildWhyYouMatchedReasons(
    baseInput({
      viewerInterests: ["a"],
      peerInterests: ["a"],
      musicScore: null,
      humorMatchingAnswers: null,
      humorComparableAnswers: null,
      humorScore: null,
      distanceKm: null,
      communicationTopic: false,
      questionAlignedCount: null,
      viewerLifestyleTags: [],
      peerLifestyleTags: [],
      viewerLanguages: [],
      peerLanguages: [],
    }),
  );
  assert.equal(reasons.length, 1);
  assert.equal(reasons[0].confidence, 0.4);
});
