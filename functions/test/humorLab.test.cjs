const test = require("node:test");
const assert = require("node:assert/strict");
const {
  calculateCompatibility,
} = require("../lib/compatibility/compatibilityEngine.js");
const {
  HUMOR_CATEGORIES,
  emptyHumorVector,
  normalizeHumorVector,
  normalizeProfileVector,
  isHumorCategory,
  clamp01,
  clamp100,
} = require("../lib/humor/categories.js");
const {
  RATING_WEIGHTS,
  ratingWeight,
  confidenceFromInteractions,
  learningRate,
  isProfileBuilding,
  defaultUserHumorProfile,
  applyFeedbackToProfile,
  cosineSimilarity,
  affinityScore,
  topStrongDims,
} = require("../lib/humor/profile.js");
const {
  EXPLORATION_FRACTION,
  scoreHumorCandidate,
  rankHumorFeed,
} = require("../lib/humor/ranking.js");
const {humorScoreForPair} = require("../lib/humor/compatibility.js");
const {
  emptySafetyFlags,
  classifyHumorSafety,
  canServeHumorContent,
} = require("../lib/humor/moderation.js");
const {applyHumorAiTagging} = require("../lib/humor/aiTagging.js");
const {
  INTERNAL_HUMOR_SEED,
  toFeedSafeContent,
  parseHumorContent,
} = require("../lib/humor/contentRepository.js");
const {
  HUMOR_RATINGS,
  HUMOR_PROFILE_VERSION,
  HUMOR_FEED_PAGE_SIZE,
  HUMOR_PROFILE_BUILDING_THRESHOLD,
} = require("../lib/humor/types.js");
const {
  resolveHumorSourceAdapter,
  InternalHumorSourceAdapter,
  LicensedApiHumorSourceAdapter,
} = require("../lib/humor/sourceAdapter.js");

function contentDoc(partial = {}) {
  return {
    contentId: partial.contentId ?? "hc_test",
    type: partial.type ?? "text",
    language: partial.language ?? "en",
    category: partial.category ?? "meme",
    humorTags: partial.humorTags ?? ["meme"],
    humorVector: normalizeHumorVector(partial.humorVector ?? {meme: 0.9}, 0),
    media: partial.media ?? {textBody: "joke"},
    safetyStatus: partial.safetyStatus ?? "approved",
    safetyFlags: emptySafetyFlags(partial.safetyFlags ?? {}),
    source: partial.source ?? {type: "internal", provider: "mevora-internal"},
    active: partial.active !== false,
    stats: partial.stats ?? {viewCount: 0, ratingCount: 0, avgRating: 0},
  };
}

test("humor categories are stable and normalize correctly", () => {
  assert.equal(HUMOR_CATEGORIES.length, 11);
  assert.ok(isHumorCategory("sarcasm"));
  assert.equal(isHumorCategory("not-a-category"), false);
  const empty = emptyHumorVector(0);
  assert.equal(empty.meme, 0);
  assert.equal(clamp01(2), 1);
  assert.equal(clamp100(150), 100);
  const content = normalizeHumorVector({meme: 2, sarcasm: -1}, 0);
  assert.equal(content.meme, 1);
  assert.equal(content.sarcasm, 0);
  const profile = normalizeProfileVector({meme: 120.4}, 50);
  assert.equal(profile.meme, 100);
  assert.equal(profile.absurd, 50);
});

test("rating weights and EMA feedback move profile toward content", () => {
  assert.equal(RATING_WEIGHTS.very_funny, 1);
  assert.equal(RATING_WEIGHTS.funny, 0.6);
  assert.equal(RATING_WEIGHTS.neutral, 0);
  assert.equal(RATING_WEIGHTS.not_funny, -0.5);
  assert.equal(RATING_WEIGHTS.not_at_all, -1);
  assert.equal(ratingWeight("funny"), 0.6);
  assert.deepEqual([...HUMOR_RATINGS], [
    "very_funny",
    "funny",
    "neutral",
    "not_funny",
    "not_at_all",
  ]);

  const profile = defaultUserHumorProfile();
  assert.equal(profile.version, HUMOR_PROFILE_VERSION);
  assert.equal(isProfileBuilding(0), true);
  assert.equal(isProfileBuilding(HUMOR_PROFILE_BUILDING_THRESHOLD), false);

  const next = applyFeedbackToProfile({
    profile,
    contentVector: {meme: 1, sarcasm: 0},
    category: "meme",
    rating: "very_funny",
  });
  assert.equal(next.interactionCount, 1);
  assert.ok(next.confidence > 0);
  assert.ok(next.vector.meme > 50);
  assert.ok(next.exploredCategories.includes("meme"));
  assert.ok(learningRate(0) > learningRate(1));
  assert.ok(confidenceFromInteractions(40) > confidenceFromInteractions(5));
});

test("affinity and cosine are deterministic", () => {
  const a = normalizeProfileVector({meme: 90, sarcasm: 80}, 50);
  const b = normalizeHumorVector({meme: 1, sarcasm: 0.8}, 0);
  const affinity = affinityScore(a, b);
  assert.ok(affinity > 0.5);
  assert.equal(cosineSimilarity(a, a), 1);
  assert.deepEqual(topStrongDims(a, 70, 2), ["meme", "sarcasm"]);
});

test("ranking uses documented weights and exploration slots", () => {
  assert.equal(EXPLORATION_FRACTION, 0.18);
  assert.equal(HUMOR_FEED_PAGE_SIZE, 12);

  const profile = defaultUserHumorProfile();
  profile.vector = normalizeProfileVector({meme: 90}, 50);
  profile.exploredCategories = ["meme"];

  const highAffinity = contentDoc({
    contentId: "high",
    category: "meme",
    humorVector: {meme: 1},
  });
  const explore = contentDoc({
    contentId: "explore",
    category: "absurd",
    humorVector: {absurd: 1},
  });

  const scored = scoreHumorCandidate({
    profile,
    content: highAffinity,
    seen: false,
    userLanguages: ["en"],
  });
  assert.ok(scored.affinity > 0);
  assert.equal(scored.novelty, 1);
  assert.ok(Math.abs(scored.total - (
    0.55 * scored.affinity +
    0.15 * scored.novelty +
    0.15 * scored.exploration +
    0.10 * scored.quality +
    0.05 * scored.language
  )) < 1e-9);

  const ranked = rankHumorFeed({
    profile,
    items: [
      {content: highAffinity, seen: false},
      {content: explore, seen: false},
      {content: contentDoc({contentId: "high"}), seen: false},
    ],
    userLanguages: ["en"],
    limit: 12,
  });
  const ids = ranked.map((item) => item.contentId);
  assert.ok(ids.includes("high"));
  assert.equal(ids.filter((id) => id === "high").length, 1);
});

test("pair humor score unavailable while building and available when ready", () => {
  const building = defaultUserHumorProfile();
  building.interactionCount = 3;
  building.confidence = 0.05;
  const early = humorScoreForPair(building, building);
  assert.equal(early.available, false);
  assert.equal(early.reason, "building");
  assert.equal(early.score, null);

  const ready = defaultUserHumorProfile();
  ready.interactionCount = 20;
  ready.confidence = 0.4;
  ready.vector = normalizeProfileVector(
    {meme: 90, sarcasm: 85, absurd: 80, silly: 50},
    50,
  );
  const peer = {
    ...ready,
    vector: normalizeProfileVector(
      {meme: 88, sarcasm: 82, absurd: 78, silly: 52},
      50,
    ),
  };
  const result = humorScoreForPair(ready, peer);
  assert.equal(result.available, true);
  assert.ok(typeof result.score === "number");
  assert.ok(result.score >= 0 && result.score <= 100);
});

test("moderation rejects hard flags and reviews borderline", () => {
  assert.equal(classifyHumorSafety(emptySafetyFlags()).status, "approved");
  assert.equal(
    classifyHumorSafety(emptySafetyFlags({minorRelated: true})).status,
    "rejected",
  );
  assert.equal(
    classifyHumorSafety(emptySafetyFlags({illegal: true})).status,
    "rejected",
  );
  assert.equal(
    classifyHumorSafety(emptySafetyFlags({extreme: true})).status,
    "rejected",
  );
  assert.equal(
    classifyHumorSafety(emptySafetyFlags({nsfw: true})).status,
    "needs_review",
  );
  assert.equal(
    canServeHumorContent({active: true, safetyStatus: "approved"}),
    true,
  );
  assert.equal(
    canServeHumorContent({active: true, safetyStatus: "needs_review"}),
    false,
  );
});

test("AI tagging is metadata-only and never used for user scoring", () => {
  const tagged = applyHumorAiTagging({
    suggestedCategory: "wordplay",
    suggestedTags: [" Pun ", "office"],
    suggestedVector: {wordplay: 0.8},
  });
  assert.equal(tagged.category, "wordplay");
  assert.deepEqual(tagged.humorTags, ["pun", "office"]);
  assert.equal(tagged.usedForUserScoring, false);
  assert.ok(tagged.humorVector.wordplay > 0);

  const fallback = applyHumorAiTagging({});
  assert.equal(fallback.category, "silly");
  assert.equal(fallback.usedForUserScoring, false);
  assert.ok(fallback.humorVector.silly >= 0.7);
});

test("internal seed is Turkish-first with real media URLs", () => {
  assert.equal(INTERNAL_HUMOR_SEED.length, 12);
  const tr = INTERNAL_HUMOR_SEED.filter((item) => item.language === "tr");
  assert.ok(tr.length >= 8);
  for (const item of INTERNAL_HUMOR_SEED) {
    assert.ok(item.media?.downloadUrl, "seed must include media URL");
    assert.ok(String(item.media.downloadUrl).startsWith("https://"));
  }
  const parsed = parseHumorContent(INTERNAL_HUMOR_SEED[0].contentId, {
    ...INTERNAL_HUMOR_SEED[0],
    safetyStatus: "approved",
    safetyFlags: emptySafetyFlags(),
    source: {type: "internal", provider: "mevora-internal"},
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
  });
  assert.ok(parsed);
  const safe = toFeedSafeContent(parsed);
  assert.equal(safe.contentId, INTERNAL_HUMOR_SEED[0].contentId);
  assert.ok(safe.media.downloadUrl);
  assert.equal("humorVector" in safe, false);
  assert.equal("safetyFlags" in safe, false);
});

test("content validation rejects empty and accepts sample video hosts", () => {
  const {validateHumorSourceItem} = require("../lib/humor/contentValidation.js");
  assert.equal(
    validateHumorSourceItem({
      sourceId: "x",
      type: "video",
      language: "tr",
      media: {downloadUrl: ""},
    }).ok,
    false,
  );
  assert.equal(
    validateHumorSourceItem({
      sourceId: "x",
      type: "video",
      language: "tr",
      media: {
        downloadUrl:
          "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
      },
    }).ok,
    true,
  );
});

test("source adapters resolve internal and licensed stubs", () => {
  const internal = resolveHumorSourceAdapter();
  assert.ok(internal instanceof InternalHumorSourceAdapter);
  assert.equal(internal.kind, "internal");
  const licensed = resolveHumorSourceAdapter("licensed_api", "partner");
  assert.ok(licensed instanceof LicensedApiHumorSourceAdapter);
  assert.equal(licensed.provider, "partner");
});

test("compatibility baseline overallScore is 80 and has no humorScore field", () => {
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
    relationship: {
      score: 100,
      alignedCount: 3,
      sharedQuestionCount: 3,
      topTopics: ["communication"],
    },
    musicScore: 80,
  });
  assert.equal(result.overallScore, 80);
  assert.equal(Object.prototype.hasOwnProperty.call(result, "humorScore"), false);
  assert.equal("humorScore" in result, false);
});

test("youtube mapper builds embed-only normalized content", () => {
  const {mapYoutubeItem, youtubeEmbedUrl} = require("../lib/humor/youtubeSource.js");
  const mapped = mapYoutubeItem(
    {
      id: {videoId: "abc123XYZ12"},
      snippet: {
        title: "Komik anlar #shorts",
        description: "türk komedi",
        publishedAt: "2024-01-01T00:00:00Z",
        thumbnails: {high: {url: "https://i.ytimg.com/vi/abc123XYZ12/hqdefault.jpg"}},
      },
    },
    "tr",
    "absurd",
  );
  assert.ok(mapped);
  assert.equal(mapped.provider, "youtube");
  assert.equal(mapped.contentUrl, null);
  assert.equal(mapped.embedUrl, youtubeEmbedUrl("abc123XYZ12"));
  assert.equal(mapped.attributionRequired, true);
  assert.equal(mapped.category, "absurd");
  const nsfw = mapYoutubeItem(
    {id: {videoId: "bad"}, snippet: {title: "xxx nsfw clip"}},
    "en",
    "meme",
  );
  assert.equal(nsfw, null);
});

test("youtube embed host is allowlisted for validation", () => {
  const {validateHumorSourceItem} = require("../lib/humor/contentValidation.js");
  assert.equal(
    validateHumorSourceItem({
      sourceId: "abc123XYZ12",
      type: "video",
      language: "tr",
      sourceUrl: "https://www.youtube.com/watch?v=abc123XYZ12",
      media: {
        downloadUrl: "https://www.youtube.com/embed/abc123XYZ12",
        embedUrl: "https://www.youtube.com/embed/abc123XYZ12",
        thumbUrl: "https://i.ytimg.com/vi/abc123XYZ12/hqdefault.jpg",
      },
    }).ok,
    true,
  );
});

test("tenor provider is disabled", () => {
  const {TENOR_API_STATUS, TenorHumorSource} = require("../lib/humor/tenorSource.js");
  assert.equal(TENOR_API_STATUS.active, false);
  assert.equal(TenorHumorSource.tryCreate(), null);
});

test("category query buckets are allowlisted and turkish-first", () => {
  const {
    HUMOR_SEARCH_BUCKETS,
    pickBucketQuery,
    BUCKET_TO_CATEGORY,
  } = require("../lib/humor/categoryQueries.js");
  assert.ok(HUMOR_SEARCH_BUCKETS.includes("fail"));
  assert.ok(HUMOR_SEARCH_BUCKETS.includes("turkish"));
  const q = pickBucketQuery("turkish", "tr", 0);
  assert.match(q, /türk|komedi|komik/i);
  assert.equal(BUCKET_TO_CATEGORY.animal, "silly");
});

test("provider diversification avoids long same-provider runs", () => {
  const {diversifyByProvider} = require("../lib/humor/feed.js");
  const items = [
    contentDoc({contentId: "a", source: {type: "licensed_api", provider: "giphy"}}),
    contentDoc({contentId: "b", source: {type: "licensed_api", provider: "giphy"}}),
    contentDoc({contentId: "c", source: {type: "licensed_api", provider: "youtube"}}),
    contentDoc({contentId: "d", source: {type: "licensed_api", provider: "giphy"}}),
  ];
  const out = diversifyByProvider(items);
  assert.equal(out.length, 4);
  assert.notEqual(out[0].source.provider, out[1].source.provider);
});
