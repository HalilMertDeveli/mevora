const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {FIXTURES, gif, clip, fakeGiphyFetch} = require("./helpers/giphyFixtures.cjs");

const {
  GIPHY_QUERY_FAMILIES,
  GiphyHumorSource,
  MAX_MP4_BYTES,
  cleanProviderTitle,
  mapGiphyClip,
  mapGiphyGif,
  pickClipRendition,
  pickGifRendition,
  pickPoster,
  selectQueryFamilies,
} = require("../lib/humor/giphySource.js");
const {
  assessProviderRelevance,
  providerSourceTrust,
} = require("../lib/humor/providerRelevance.js");
const {
  inferProviderCategory,
  ingestHumorSourceItem,
  syncHumorFromGiphy,
} = require("../lib/humor/ingest.js");
const {
  listCalibrationPool,
  parseHumorContent,
  toFeedSafeContent,
} = require("../lib/humor/contentRepository.js");
const {HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");
const {TRUST_QUALITY_PRIOR_BOOST, scoreHumorCandidate} = require("../lib/humor/ranking.js");
const {defaultUserHumorProfile} = require("../lib/humor/profile.js");

const FAKE_KEY = "fixture-key-not-a-real-giphy-key";
const TR_FAMILY = GIPHY_QUERY_FAMILIES.find((f) => f.query === "komik tepki");
const SARCASM_FAMILY = GIPHY_QUERY_FAMILIES.find((f) => f.query === "sarcastic reaction");

function mapped(fixture, family = TR_FAMILY) {
  const outcome = mapGiphyGif(fixture, {language: "tr", family});
  assert.equal(outcome.ok, true, `mapping failed: ${outcome.reason}`);
  return outcome.item;
}

function source(fetchOptions = {}, options = {}) {
  const fake = fakeGiphyFetch(fetchOptions);
  return {
    source: new GiphyHumorSource(FAKE_KEY, {fetchImpl: fake.fetchImpl, ...options}),
    calls: fake.calls,
  };
}

/** Every string anywhere in a value. */
function stringsIn(value, out = []) {
  if (typeof value === "string") out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => stringsIn(v, out));
  else if (value && typeof value === "object") Object.values(value).forEach((v) => stringsIn(v, out));
  return out;
}

// --------------------------------------------------------------------------
// Query families
// --------------------------------------------------------------------------

describe("query families", () => {
  it("are intentional, Turkish first, each probing a real humor category", () => {
    const tr = GIPHY_QUERY_FAMILIES.filter((f) => f.language === "tr").map((f) => f.query);
    const en = GIPHY_QUERY_FAMILIES.filter((f) => f.language === "en").map((f) => f.query);
    for (const q of ["komik tepki", "komik sahne", "dizi komik", "film komik", "komedi",
      "kahkaha", "şaşkınlık", "sarkazm", "ironi", "türk meme", "sitcom"]) {
      assert.ok(tr.includes(q), `missing TR query ${q}`);
    }
    for (const q of ["funny reaction", "comedy reaction", "sitcom reaction", "funny tv",
      "comedy scene", "movie reaction", "sarcastic reaction", "awkward reaction",
      "absurd comedy", "dry humor", "laughing reaction"]) {
      assert.ok(en.includes(q), `missing EN query ${q}`);
    }
    for (const family of GIPHY_QUERY_FAMILIES) {
      assert.ok(family.query.length <= 50, family.query);
      assert.ok(HUMOR_CATEGORIES.includes(family.category), family.query);
    }
    // The bare catch-alls that pulled in wallpapers are gone.
    for (const bare of ["funny", "lol", "meme", "komik"]) {
      assert.equal(tr.includes(bare) || en.includes(bare), false, `bare query ${bare}`);
    }
  });

  it("rotate deterministically, TR before EN for a Turkish sync", () => {
    const a = selectQueryFamilies("tr", 4, 3);
    const b = selectQueryFamilies("tr", 4, 3);
    assert.deepEqual(a, b, "same rotation must give the same queries");
    assert.ok(a.every((f) => f.language === "tr"));
    assert.notDeepEqual(
      selectQueryFamilies("tr", 4, 0).map((f) => f.query),
      a.map((f) => f.query),
      "a different rotation starts elsewhere",
    );
    const all = selectQueryFamilies("tr", 100, 0);
    const firstEn = all.findIndex((f) => f.language === "en");
    assert.ok(firstEn > 0 && all.slice(firstEn).every((f) => f.language === "en"));
    assert.ok(selectQueryFamilies("en", 5, 7).every((f) => f.language === "en"));
  });

  it("no randomness drives provider selection", () => {
    for (const file of ["giphySource.ts", "ingest.ts", "providerRelevance.ts"]) {
      const text = fs.readFileSync(path.join(__dirname, "..", "src", "humor", file), "utf8");
      assert.equal(/Math\.random/.test(text), false, `${file} uses Math.random`);
    }
  });
});

// --------------------------------------------------------------------------
// Mapping: each item keeps its own media, poster, title and credit
// --------------------------------------------------------------------------

describe("GIF mapping", () => {
  it("preserves each item's own media, poster, caption and attribution", () => {
    const a = mapped(FIXTURES.turkishReaction);
    const b = mapped(FIXTURES.sitcomReaction);

    assert.equal(a.sourceId, "trReact01");
    assert.equal(a.type, "video");
    assert.ok(a.media.downloadUrl.includes("/trReact01/"), a.media.downloadUrl);
    assert.ok(a.media.thumbUrl.includes("/trReact01/"), a.media.thumbUrl);
    assert.equal(a.media.textBody, "Komik Tepki");
    assert.equal(a.title, "Komik Tepki");
    assert.deepEqual(a.attribution, {
      provider: "giphy",
      displayName: "GAİN",
      username: "gainmedya",
      sourceUrl: "https://giphy.com/gifs/komik-tepki-gif-by-gain-trReact01",
      verified: true,
    });
    assert.equal(a.sourceUrl, a.attribution.sourceUrl);

    assert.ok(b.media.downloadUrl.includes("/sitcom01/"));
    assert.ok(b.media.thumbUrl.includes("/sitcom01/"));
    assert.equal(b.media.textBody, "Sitcom Reaction");
    assert.equal(b.attribution.username, "couchclips");
    assert.equal(b.attribution.verified, false);

    // No cross-contamination: nothing of one item appears on the other.
    for (const s of stringsIn(b.media)) {
      assert.equal(s.includes("trReact01"), false, `sitcom item carries ${s}`);
    }
  });

  it("never invents a caption: the text is the item's own title or null", () => {
    const fixtures = Object.values(FIXTURES);
    for (const fixture of fixtures) {
      const outcome = mapGiphyGif(fixture, {language: "tr", family: TR_FAMILY});
      if (!outcome.ok) continue;
      const body = outcome.item.media.textBody;
      if (body === null) continue;
      assert.ok(
        fixture.title.replace(/\s+/g, " ").toLowerCase().includes(body.toLowerCase()),
        `${fixture.id}: caption "${body}" is not from title "${fixture.title}"`,
      );
    }
    assert.equal(mapped(FIXTURES.genericTitle).media.textBody, null);
    assert.equal(mapped(FIXTURES.usernameTitle).media.textBody, null);
    // Mapping twice gives the same caption: nothing random.
    assert.deepEqual(mapped(FIXTURES.laughing), mapped(FIXTURES.laughing));
  });

  it("rejects items without a usable MP4 instead of guessing", () => {
    for (const name of ["noMp4", "insecureMedia", "offHostMedia"]) {
      const outcome = mapGiphyGif(FIXTURES[name], {language: "tr", family: TR_FAMILY});
      assert.equal(outcome.ok, false, name);
      assert.equal(outcome.reason, "missing-media", name);
    }
    assert.equal(mapGiphyGif({}, {language: "tr"}).reason, "missing-id");
  });
});

describe("caption cleaning", () => {
  const cases = [
    ["Komik Tepki GIF by Gain", {username: "gainmedya"}, "Komik Tepki"],
    ["Happy Dance GIF", {}, "Happy Dance"],
    ["Sitcom  Reaction   GIF", {}, "Sitcom Reaction"],
    ["Excited Season 2 GIF by The Office", {displayName: "The Office"}, "Excited Season 2"],
    ["Eye Roll Sticker by Someone", {}, "Eye Roll"],
    ["Oh No by couchclips", {username: "couchclips"}, "Oh No"],
    ["Stand by me GIF", {}, "Stand by me"],
    ["  Yine mi?  ", {}, "Yine mi?"],
    ["GIF", {}, null],
    ["gif by Netflix", {}, null],
    ["Untitled", {}, null],
    ["", {}, null],
    ["   ", {}, null],
    ["!!! ...", {}, null],
    ["couchclips GIF", {username: "couchclips"}, null],
    ["The Office", {displayName: "The Office"}, null],
    [null, {}, null],
    [42, {}, null],
  ];
  for (const [raw, who, expected] of cases) {
    it(`${JSON.stringify(raw)} → ${JSON.stringify(expected)}`, () => {
      assert.equal(cleanProviderTitle(raw, who), expected);
    });
  }

  it("bounds a runaway title without adding anything", () => {
    const long = "ha ".repeat(200);
    const cleaned = cleanProviderTitle(long, {});
    assert.ok(cleaned.length <= 200);
    assert.ok(long.startsWith(cleaned));
  });
});

// --------------------------------------------------------------------------
// Rendition and poster choice
// --------------------------------------------------------------------------

describe("rendition selection", () => {
  const images = (sizes, dims) => gif({id: "r1", title: "x", imageOptions: {sizes, dims}}).images;

  it("takes the highest-resolution MP4 within the size budget", () => {
    const pick = pickGifRendition(
      images({original_mp4: 5_000_000, fixed_height: 1_200_000, downsized_small: 400_000}),
    );
    assert.equal(pick.name, "fixed_height");
    assert.ok(pick.url.endsWith("/200.mp4"));
    assert.equal(pick.sizeBytes, 1_200_000);

    const small = pickGifRendition(
      images({original_mp4: 2_000_000, fixed_height: 700_000, downsized_small: 150_000}),
    );
    assert.equal(small.name, "original_mp4", "the original fits, and it is the largest");
    assert.ok(MAX_MP4_BYTES >= 2_000_000 && MAX_MP4_BYTES <= 3_000_000);
  });

  it("falls back to the smallest known size when nothing fits", () => {
    const pick = pickGifRendition(
      images({original_mp4: 9_000_000, fixed_height: 4_000_000, downsized_small: 3_100_000}),
    );
    assert.equal(pick.name, "downsized_small");
  });

  it("falls back to the lightest rendition when no size is reported", () => {
    const pick = pickGifRendition(
      images({original_mp4: null, fixed_height: null, downsized_small: null}),
    );
    assert.equal(pick.name, "downsized_small");
  });

  it("only considers https URLs on allowed hosts", () => {
    const mixed = images({original_mp4: 1_000_000, fixed_height: 500_000, downsized_small: 100_000});
    mixed.original_mp4.mp4 = "http://media1.giphy.com/media/r1/giphy.mp4";
    mixed.fixed_height.mp4 = "https://giphy.com.attacker.tld/media/r1/200.mp4";
    const pick = pickGifRendition(mixed);
    assert.equal(pick.name, "downsized_small");
    assert.equal(pickGifRendition(null), null);
  });

  it("uses a real still of the same item as the poster", () => {
    const img = images({});
    assert.equal(pickPoster(img), "https://media1.giphy.com/media/r1/200_s.gif");
    delete img.fixed_height_still;
    assert.equal(pickPoster(img), "https://media1.giphy.com/media/r1/giphy_s.gif");
    img.original_still.url = "http://media1.giphy.com/media/r1/giphy_s.gif";
    assert.equal(pickPoster(img), null, "no insecure poster; null beats a wrong one");
  });

  it("maps a clip to 480p (else 360p) with its real duration", () => {
    const c = clip({id: "clip01", title: "Awkward Silence Reaction", username: "nbc", verified: true});
    assert.equal(pickClipRendition(c).name, "480p");
    const outcome = mapGiphyClip(c, {language: "en", family: SARCASM_FAMILY});
    assert.equal(outcome.ok, true);
    assert.ok(outcome.item.media.downloadUrl.endsWith("/480p.mp4"));
    assert.equal(outcome.item.media.durationMs, 7500);
    assert.equal(outcome.item.media.aspectRatio, 854 / 480);
    assert.equal(outcome.item.media.textBody, "Awkward Silence Reaction");
    assert.equal(outcome.item.origin, "clip");

    delete c.video.assets["480p"];
    assert.equal(pickClipRendition(c).name, "360p");
    delete c.video.assets["360p"];
    delete c.video.assets["720p"];
    assert.equal(pickClipRendition(c), null, "never 1080p or 4k");
  });
});

// --------------------------------------------------------------------------
// Relevance and rating filters
// --------------------------------------------------------------------------

describe("relevance filter", () => {
  const verdict = (name, family = TR_FAMILY) => assessProviderRelevance(mapped(FIXTURES[name], family));

  it("accepts reaction, sitcom and comedy items", () => {
    for (const name of ["turkishReaction", "sitcomReaction", "laughing", "genericTitle", "usernameTitle"]) {
      assert.deepEqual(verdict(name), {ok: true, basis: "lexicon"}, name);
    }
  });

  it("accepts a verified entertainment account matched by a comedy query only", () => {
    assert.deepEqual(verdict("verifiedNoWords"), {ok: true, basis: "verified-comedy-query"});
    assert.deepEqual(verdict("unverifiedNoWords"), {ok: false, reason: "not-humor"});
    // Without a comedy query behind it, verification alone is not enough.
    assert.equal(verdict("verifiedNoWords", null).ok, false);
  });

  it("rejects landscapes, wallpapers, loops, greetings and stickers", () => {
    for (const name of ["landscape", "funnyWallpaper", "greeting", "turkishGreeting", "abstractLoop"]) {
      assert.deepEqual(verdict(name), {ok: false, reason: "off-topic"}, name);
    }
    assert.deepEqual(verdict("sticker"), {ok: false, reason: "sticker"});
  });

  it("accepts only g / pg / pg-13", () => {
    assert.deepEqual(verdict("ratedR"), {ok: false, reason: "rating"});
    assert.deepEqual(verdict("unrated"), {ok: false, reason: "rating"});
    for (const rating of ["g", "pg", "pg-13", "PG-13"]) {
      const item = mapped(gif({id: `ok_${rating}`, title: "Funny Reaction GIF", rating}));
      assert.equal(assessProviderRelevance(item).ok, true, rating);
    }
    for (const rating of ["r", "nc-17", "y", "unrated"]) {
      const item = mapped(gif({id: `no_${rating}`, title: "Funny Reaction GIF", rating}));
      assert.deepEqual(assessProviderRelevance(item), {ok: false, reason: "rating"}, rating);
    }
  });

  it("rejects an item with no media", () => {
    const item = {...mapped(FIXTURES.sitcomReaction), media: {downloadUrl: ""}};
    assert.deepEqual(assessProviderRelevance(item), {ok: false, reason: "missing-media"});
  });
});

// --------------------------------------------------------------------------
// Trust tiers and category inference
// --------------------------------------------------------------------------

describe("trust tiers", () => {
  it("verified or known studio accounts are verified_provider; the rest provider", () => {
    assert.equal(providerSourceTrust(mapped(FIXTURES.turkishReaction).attribution), "verified_provider");
    assert.equal(providerSourceTrust(mapped(FIXTURES.verifiedNoWords).attribution), "verified_provider");
    // Known network account, not flagged verified by the provider.
    assert.equal(providerSourceTrust(mapped(FIXTURES.laughing).attribution), "verified_provider");
    assert.equal(providerSourceTrust(mapped(FIXTURES.sitcomReaction).attribution), "provider");
    assert.equal(providerSourceTrust(null), "provider");
  });

  it("gives verified content a small prior boost that real ratings override", () => {
    assert.deepEqual(TRUST_QUALITY_PRIOR_BOOST, {
      curated: 0,
      verified_provider: 0.08,
      provider: 0,
      qa_fixture: 0,
    });
    const base = {
      contentId: "x",
      type: "video",
      language: "tr",
      category: "silly",
      humorTags: [],
      humorVector: {silly: 0.6},
      media: {},
      safetyStatus: "approved",
      safetyFlags: {},
      source: {type: "licensed_api", provider: "giphy"},
      active: true,
      stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    };
    const score = (content) =>
      scoreHumorCandidate({
        profile: defaultUserHumorProfile(),
        content,
        seen: false,
        userLanguages: ["tr"],
      });
    const plain = score({...base, sourceTrust: "provider"});
    const verified = score({...base, sourceTrust: "verified_provider"});
    assert.ok(verified.quality > plain.quality);
    assert.ok(verified.total - plain.total <= 0.0081, "the boost stays small");
    // With 20+ ratings the prior (and therefore the boost) no longer counts.
    const rated = {viewCount: 30, ratingCount: 30, avgRating: 0.2};
    assert.equal(
      score({...base, sourceTrust: "verified_provider", stats: rated}).quality,
      score({...base, sourceTrust: "provider", stats: rated}).quality,
    );
  });
});

describe("category inference", () => {
  it("uses the query family as the primary signal, with modest weights", () => {
    const item = mapped(FIXTURES.unverifiedNoWords, SARCASM_FAMILY);
    const inferred = inferProviderCategory(item);
    assert.equal(inferred.category, "sarcasm");
    assert.ok(inferred.vector.sarcasm <= 0.6);
  });

  it("adds a keyword dimension as secondary, never above the query's", () => {
    const item = mapped(gif({id: "aw01", title: "Awkward Moment GIF"}), SARCASM_FAMILY);
    const inferred = inferProviderCategory(item);
    assert.equal(inferred.category, "sarcasm");
    assert.ok(inferred.vector.cringe > 0 && inferred.vector.cringe < inferred.vector.sarcasm);
  });

  it("without a query it falls back to keywords, and never claims high confidence", () => {
    const item = {...mapped(FIXTURES.sitcomReaction), queryCategory: null};
    const inferred = inferProviderCategory(item);
    for (const value of Object.values(inferred.vector)) {
      assert.ok(value <= 0.6);
    }
    const ironman = {...mapped(gif({id: "im01", title: "Ironman Flying GIF"})), queryCategory: null};
    assert.notEqual(inferProviderCategory(ironman).category, "sarcasm", "ironman is not irony");
  });
});

// --------------------------------------------------------------------------
// The sync pipeline end to end (fake fetch, in-memory Firestore)
// --------------------------------------------------------------------------

const BATCH = [
  FIXTURES.turkishReaction,
  FIXTURES.sitcomReaction,
  FIXTURES.laughing,
  FIXTURES.verifiedNoWords,
  FIXTURES.unverifiedNoWords,
  FIXTURES.genericTitle,
  FIXTURES.landscape,
  FIXTURES.funnyWallpaper,
  FIXTURES.greeting,
  FIXTURES.sticker,
  FIXTURES.ratedR,
  FIXTURES.noMp4,
  FIXTURES.offHostMedia,
  FIXTURES.sitcomReactionRepost,
  FIXTURES.sameMediaDifferentId,
];

async function runSync({fetchOptions = {}, sourceOptions = {}, db = createFakeFirestore({}), ...rest} = {}) {
  const {source: giphy, calls} = source({gifsByQuery: {"*": BATCH}, ...fetchOptions}, sourceOptions);
  const logs = [];
  const result = await syncHumorFromGiphy({
    db,
    language: "tr",
    limit: 40,
    probe: false,
    source: giphy,
    rotation: 0,
    queryCount: 1,
    log: (message, meta) => logs.push({message, meta}),
    ...rest,
  });
  return {result, db, calls, logs};
}

function providerDocs(db) {
  return db
    .paths()
    .filter((p) => p.startsWith("humorContent/ext_giphy_"))
    .map((p) => db.read(p));
}

describe("provider sync", () => {
  it("keeps only relevant, unique items and reports why the rest were dropped", async () => {
    const {result, db} = await runSync();
    assert.equal(result.configured, true);
    assert.deepEqual(result.queries, [selectQueryFamilies("tr", 1, 0)[0].query]);
    assert.equal(result.fetched, BATCH.length);
    assert.equal(result.accepted, 5);
    assert.equal(result.duplicates, 2);
    assert.deepEqual(result.rejected, {
      "missing-media": 2,
      "not-humor": 1,
      "off-topic": 3,
      sticker: 1,
      rating: 1,
    });
    assert.equal(result.clipsAvailable, false);
    assert.deepEqual(result.errors, {});

    const ids = providerDocs(db).map((d) => d.contentId).sort();
    assert.deepEqual(ids, [
      "ext_giphy_generic01",
      "ext_giphy_laugh01",
      "ext_giphy_office01",
      "ext_giphy_sitcom01",
      "ext_giphy_trReact01",
    ]);
  });

  it("stores each item's own media, poster, caption, provenance and trust", async () => {
    const {db} = await runSync();
    const doc = db.read("humorContent/ext_giphy_trReact01");
    assert.equal(doc.type, "video");
    assert.ok(doc.media.downloadUrl.includes("/trReact01/"));
    assert.ok(doc.media.thumbUrl.includes("/trReact01/200_s.gif"));
    assert.equal(doc.media.textBody, "Komik Tepki");
    assert.equal(doc.sourceId, "trReact01");
    assert.equal(doc.sourceUrl, "https://giphy.com/gifs/komik-tepki-gif-by-gain-trReact01");
    assert.equal(doc.source.provider, "giphy");
    assert.equal(doc.source.type, "licensed_api");
    assert.equal(doc.sourceTrust, "verified_provider");
    assert.deepEqual(doc.attribution, {
      provider: "giphy",
      displayName: "GAİN",
      username: "gainmedya",
      sourceUrl: "https://giphy.com/gifs/komik-tepki-gif-by-gain-trReact01",
      verified: true,
    });
    assert.equal(doc.category, TR_FAMILY.category, "query category is primary");

    const generic = db.read("humorContent/ext_giphy_generic01");
    assert.equal(generic.media.textBody, null, "a generic title becomes no caption");
    assert.equal(generic.sourceTrust, "provider");
  });

  it("never makes provider content calibration-eligible", async () => {
    const {db} = await runSync();
    const docs = providerDocs(db);
    assert.ok(docs.length > 0);
    for (const doc of docs) {
      assert.equal(doc.calibrationEligible, false, doc.contentId);
      assert.equal(doc.calibrationSlot, null, doc.contentId);
      assert.equal(doc.calibrationVersion, 0, doc.contentId);
    }
    const pool = await listCalibrationPool(db, {calibrationVersion: HUMOR_CALIBRATION_VERSION});
    assert.deepEqual(pool, []);
  });

  it("never rewrites an item already in the catalogue", async () => {
    const first = await runSync();
    const before = first.db.read("humorContent/ext_giphy_sitcom01");
    first.db._store.set("humorContent/ext_giphy_sitcom01", {...before, active: false});
    const second = await runSync({db: first.db});
    assert.equal(second.result.accepted, 0);
    assert.equal(second.result.duplicates, 2 + 5);
    assert.equal(first.db.read("humorContent/ext_giphy_sitcom01").active, false);
  });

  it("falls back to GIF search when Clips answers 401/403/404", async () => {
    for (const status of [401, 403, 404]) {
      const {result, calls} = await runSync({
        fetchOptions: {clipsStatus: status},
        sourceOptions: {clipsEnabled: true},
        queryCount: 2,
      });
      assert.equal(result.clipsAvailable, false, `status ${status}`);
      assert.deepEqual(result.errors, {}, `status ${status} must be silent`);
      assert.equal(result.accepted, 5, `status ${status}`);
      // Asked once, then left alone for the rest of the sync.
      assert.equal(calls.filter((u) => u.pathname.endsWith("/clips/search")).length, 1);
    }
  });

  it("does not call Clips at all unless enabled", async () => {
    const {calls, result} = await runSync({fetchOptions: {clipsStatus: 200}});
    assert.equal(calls.some((u) => u.pathname.endsWith("/clips/search")), false);
    assert.equal(result.clipsAvailable, false);
  });

  it("ingests clips at 480p when Clips access is granted", async () => {
    const c = clip({id: "clip01", title: "Awkward Reaction", username: "nbc", verified: true});
    const {result, db} = await runSync({
      fetchOptions: {clipsStatus: 200, clipsByQuery: {"*": [c]}},
      sourceOptions: {clipsEnabled: true},
    });
    assert.equal(result.clipsAvailable, true);
    const doc = db.read("humorContent/ext_giphy_clip01");
    assert.ok(doc.media.downloadUrl.endsWith("/480p.mp4"));
    assert.equal(doc.media.durationMs, 7500);
    assert.equal(doc.media.textBody, "Awkward Reaction");
    assert.equal(doc.sourceTrust, "verified_provider");
  });

  it("counts a Clips server error but still runs the GIF search", async () => {
    const {result} = await runSync({
      fetchOptions: {clipsStatus: 500},
      sourceOptions: {clipsEnabled: true},
    });
    assert.deepEqual(result.errors, {"giphy-clips-http-500": 1});
    assert.equal(result.accepted, 5);
  });

  it("reports a failing GIF search as an error without the URL", async () => {
    const {result, logs} = await runSync({fetchOptions: {gifsStatus: 429}});
    assert.equal(result.accepted, 0);
    assert.deepEqual(result.errors, {"giphy-http-429": 1});
    assert.equal(JSON.stringify(logs).includes(FAKE_KEY), false);
  });

  it("returns fewer items rather than filler", async () => {
    const {result} = await runSync({
      fetchOptions: {gifsByQuery: {"*": [FIXTURES.landscape, FIXTURES.greeting, FIXTURES.sitcomReaction]}},
    });
    assert.equal(result.accepted, 1);
  });

  it("logs one summary line with counts only: no key, no URL", async () => {
    const {logs, calls} = await runSync();
    assert.equal(logs.length, 1);
    assert.equal(logs[0].message, "humor provider sync");
    const serialized = JSON.stringify(logs);
    assert.equal(serialized.includes(FAKE_KEY), false, "the API key reached the log");
    assert.equal(/api_key|https?:\/\//i.test(serialized), false, `URL in log: ${serialized}`);
    assert.equal(logs[0].meta.accepted, 5);
    // The key did go to the API, as a query parameter, with a bounded query.
    assert.ok(calls.every((u) => u.searchParams.get("api_key") === FAKE_KEY));
    assert.ok(calls.every((u) => (u.searchParams.get("q") ?? "").length <= 50));
    assert.ok(calls.every((u) => u.hostname === "api.giphy.com"));
  });

  it("is unconfigured, and harmless, without a key", async () => {
    const previous = process.env.GIPHY_API_KEY;
    delete process.env.GIPHY_API_KEY;
    try {
      const result = await syncHumorFromGiphy({db: createFakeFirestore({}), log: () => {}});
      assert.equal(result.configured, false);
      assert.equal(result.accepted, 0);
    } finally {
      if (previous !== undefined) process.env.GIPHY_API_KEY = previous;
    }
  });
});

// --------------------------------------------------------------------------
// Direct ingest and the K1 feed payload
// --------------------------------------------------------------------------

describe("feed payload attribution (K1)", () => {
  it("carries the provider credit for provider items", async () => {
    const db = createFakeFirestore({});
    const item = mapped(FIXTURES.sitcomReaction);
    const written = await ingestHumorSourceItem(db, item, "giphy", {probe: false});
    assert.equal(written.upserted, true);
    const card = toFeedSafeContent(
      parseHumorContent(written.contentId, db.read(`humorContent/${written.contentId}`)),
    );
    assert.deepEqual(Object.keys(card.attribution).sort(), [
      "displayName",
      "provider",
      "sourceUrl",
      "username",
      "verified",
    ]);
    assert.deepEqual(card.attribution, {
      provider: "giphy",
      displayName: "couchclips",
      username: "couchclips",
      sourceUrl: "https://giphy.com/gifs/sitcom-reaction-gif-sitcom01",
      verified: false,
    });
    assert.equal(card.media.textBody, "Sitcom Reaction");
    assert.ok(card.media.thumbUrl.endsWith("/sitcom01/200_s.gif"), "thumbUrl is the poster");
  });

  it("is null for Mevora-authored content, even if a doc claims otherwise", () => {
    const parsed = parseHumorContent("hc_x", {
      category: "dry",
      type: "text",
      media: {textBody: "Evet."},
      source: {type: "internal", provider: "mevora-qa-seed"},
      attribution: {provider: "giphy", username: "spoof", verified: true},
      safetyStatus: "approved",
      active: true,
    });
    assert.equal(toFeedSafeContent(parsed).attribution, null);
    assert.equal(parsed.sourceTrust, "curated");
  });

  it("parses legacy provider docs without trust or attribution", () => {
    const parsed = parseHumorContent("ext_giphy_old", {
      category: "meme",
      type: "video",
      media: {downloadUrl: "https://media.giphy.com/media/old/giphy.mp4"},
      source: {type: "licensed_api", provider: "giphy"},
      safetyStatus: "approved",
      active: true,
    });
    assert.equal(parsed.sourceTrust, "provider");
    assert.equal(toFeedSafeContent(parsed).attribution, null);
  });

  it("a provider write cannot claim the curated tier or an anchor slot", async () => {
    const db = createFakeFirestore({});
    const {upsertHumorContentDoc} = require("../lib/humor/contentRepository.js");
    await upsertHumorContentDoc(db, {
      contentId: "ext_giphy_claim",
      type: "video",
      language: "tr",
      category: "meme",
      humorVector: {meme: 0.9},
      media: {downloadUrl: "https://media.giphy.com/media/c/giphy.mp4"},
      safetyStatus: "approved",
      active: true,
      sourceType: "licensed_api",
      provider: "giphy",
      sourceTrust: "curated",
      calibration: {eligible: false, slot: "anchor_meme"},
    });
    const stored = db.read("humorContent/ext_giphy_claim");
    assert.equal(stored.sourceTrust, "provider");
    assert.equal(stored.calibrationSlot, null);
  });
});
