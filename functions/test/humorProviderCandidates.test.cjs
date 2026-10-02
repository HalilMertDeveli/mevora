const {describe, it, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");
const {FIXTURES, fakeGiphyFetch} = require("./helpers/giphyFixtures.cjs");

/**
 * The curator's candidate search: an admin-only, emulator-only callable that
 * returns GIPHY candidates for a human to pick the curated catalogue from,
 * and writes nothing. Plus the dev tool that drives it.
 */
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

const humor = require("../lib/humor/index.js");
const {
  DEFAULT_CANDIDATES_PER_QUERY,
  parseProviderCandidateSearchInput,
  searchProviderCandidates,
} = require("../lib/humor/providerCandidates.js");
const {GiphyHumorSource} = require("../lib/humor/giphySource.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");

const FAKE_KEY = "fixture-key-not-a-real-giphy-key";
const ADMIN = "admin-curator";
const USER = "plain-user";

function source(fetchOptions = {}) {
  const fake = fakeGiphyFetch(fetchOptions);
  return {source: new GiphyHumorSource(FAKE_KEY, {fetchImpl: fake.fetchImpl}), calls: fake.calls};
}

function input(overrides = {}) {
  const parsed = parseProviderCandidateSearchInput({queries: ["sitcom reaction"], ...overrides});
  assert.equal(parsed.ok, true, JSON.stringify(parsed));
  return parsed.value;
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    return true;
  });
}

describe("candidate search input", () => {
  it("defaults: 25 per query, Turkish, offset 0, up to pg-13, no dimension", () => {
    assert.deepEqual(input(), {
      queries: ["sitcom reaction"],
      perQuery: DEFAULT_CANDIDATES_PER_QUERY,
      lang: "tr",
      offset: 0,
      rating: "pg-13",
      dimension: null,
    });
  });

  it("normalises and de-duplicates queries", () => {
    assert.deepEqual(input({queries: ["  dry   humor ", "dry humor", "deadpan"]}).queries, [
      "dry humor",
      "deadpan",
    ]);
  });

  it("rejects anything out of bounds, naming the field", () => {
    const bad = [
      [{queries: []}, "queries"],
      [{queries: "sitcom"}, "queries"],
      [{queries: Array.from({length: 13}, (_, i) => `q${i}`)}, "queries"],
      [{queries: ["x".repeat(51)]}, "queries"],
      [{queries: [42]}, "queries"],
      [{queries: ["  "]}, "queries"],
      [{queries: ["ok"], perQuery: 0}, "perQuery"],
      [{queries: ["ok"], perQuery: 51}, "perQuery"],
      [{queries: ["ok"], perQuery: 2.5}, "perQuery"],
      [{queries: ["ok"], offset: -1}, "offset"],
      [{queries: ["ok"], offset: 5000}, "offset"],
      [{queries: ["ok"], lang: "de"}, "lang"],
      [{queries: ["ok"], rating: "r"}, "rating"],
      [{queries: ["ok"], dimension: "slapstick"}, "dimension"],
    ];
    for (const [data, field] of bad) {
      assert.deepEqual(parseProviderCandidateSearchInput(data), {ok: false, field}, JSON.stringify(data));
    }
    assert.deepEqual(parseProviderCandidateSearchInput(null), {ok: false, field: "queries"});
  });
});

describe("searchProviderCandidates", () => {
  it("returns each item's own title, credit, rating, renditions and still", async () => {
    const {source: src} = source({gifsByQuery: {"*": [FIXTURES.turkishReaction]}});
    const result = await searchProviderCandidates(src, input({lang: "tr", dimension: "silly"}));
    assert.equal(result.candidates.length, 1);
    const c = result.candidates[0];
    assert.equal(c.giphyId, "trReact01");
    assert.equal(c.proposedContentId, "hc_gif_trReact01");
    assert.equal(c.title, "Komik Tepki");
    assert.equal(c.rawTitle, "Komik Tepki GIF by Gain");
    assert.equal(c.username, "gainmedya");
    assert.equal(c.displayName, "GAİN");
    assert.equal(c.verified, true);
    assert.equal(c.rating, "pg");
    assert.equal(c.providerTrust, "verified_provider");
    assert.equal(c.sourceUrl, "https://giphy.com/gifs/komik-tepki-gif-by-gain-trReact01");
    assert.deepEqual(c.media.rendition, {
      name: "original.webp",
      url: "https://media1.giphy.com/media/trReact01/giphy.webp",
      sizeBytes: 1_200_000,
      width: 480,
      height: 270,
      mimeHint: "image/webp",
    });
    assert.equal(c.media.originalWebp.sizeBytes, 1_200_000);
    assert.equal(c.media.stillUrl, "https://media1.giphy.com/media/trReact01/200_s.gif");
    assert.equal(c.media.stableWebpUrl, "https://media.giphy.com/media/trReact01/giphy.webp");
    assert.equal(c.media.stableStillUrl, "https://media.giphy.com/media/trReact01/giphy_s.gif");
    assert.equal(c.media.width, 480);
    assert.equal(c.media.height, 270);
    assert.equal(c.media.aspectRatio, 1.778);
    assert.deepEqual(c.relevance, {ok: true, basis: "lexicon", reason: null});
  });

  it("shows an oversized original and the smaller rendition that would be served", async () => {
    const big = {...FIXTURES.sitcomReaction};
    big.images = {
      ...big.images,
      original: {...big.images.original, webp_size: "4000000"},
    };
    const {source: src} = source({gifsByQuery: {"*": [big]}});
    const [c] = (await searchProviderCandidates(src, input())).candidates;
    assert.equal(c.media.originalWebp.sizeBytes, 4_000_000);
    assert.equal(c.media.rendition.name, "downsized_medium");
  });

  it("keeps rejected items, with the relevance filter's reason", async () => {
    const {source: src} = source({
      gifsByQuery: {"*": [FIXTURES.landscape, FIXTURES.ratedR, FIXTURES.sticker, FIXTURES.noMp4]},
    });
    const result = await searchProviderCandidates(src, input());
    const reasons = Object.fromEntries(result.candidates.map((c) => [c.giphyId, c.relevance.reason]));
    assert.deepEqual(reasons, {
      land01: "off-topic",
      rated01: "rating",
      stk01: "sticker",
      nomp401: "missing-media",
    });
    assert.equal(result.counts.relevant, 0);
    assert.equal(result.counts.unique, 4);
  });

  it("lets a known dimension vouch for a verified studio item, and only then", async () => {
    const {source: src} = source({gifsByQuery: {"*": [FIXTURES.verifiedNoWords]}});
    const withDim = await searchProviderCandidates(src, input({dimension: "dry"}));
    assert.deepEqual(withDim.candidates[0].relevance, {ok: true, basis: "verified-comedy-query", reason: null});
    const without = await searchProviderCandidates(src, input());
    assert.equal(without.candidates[0].relevance.reason, "not-humor");
  });

  it("merges an item several queries returned, keeping first-seen order and rank", async () => {
    const {source: src, calls} = source({
      gifsByQuery: {
        "sitcom reaction": [FIXTURES.sitcomReaction, FIXTURES.laughing],
        "laughing reaction": [FIXTURES.laughing],
      },
    });
    const result = await searchProviderCandidates(
      src,
      input({queries: ["sitcom reaction", "laughing reaction"], perQuery: 10, offset: 20, lang: "en"}),
    );
    assert.deepEqual(result.candidates.map((c) => c.giphyId), ["sitcom01", "laugh01"]);
    assert.deepEqual(result.candidates[1].queries, ["sitcom reaction", "laughing reaction"]);
    assert.equal(result.candidates[1].rank, 21);
    assert.deepEqual(result.counts, {received: 3, unique: 2, relevant: 2});
    assert.deepEqual(calls.map((u) => [u.searchParams.get("q"), u.searchParams.get("limit"),
      u.searchParams.get("offset"), u.searchParams.get("lang")]), [
      ["sitcom reaction", "10", "20", "en"],
      ["laughing reaction", "10", "20", "en"],
    ]);
  });

  it("reports a failing query by status only and carries on", async () => {
    const {source: src} = source({gifsStatus: 429});
    const result = await searchProviderCandidates(src, input({queries: ["a", "b"]}));
    assert.deepEqual(result.queries.map((q) => q.error), ["giphy-http-429", "giphy-http-429"]);
    assert.equal(result.candidates.length, 0);
  });

  it("never returns the API key", async () => {
    const {source: src} = source({gifsByQuery: {"*": Object.values(FIXTURES)}});
    const result = await searchProviderCandidates(src, input());
    const serialized = JSON.stringify(result);
    assert.equal(serialized.includes(FAKE_KEY), false);
    assert.equal(/api_key/i.test(serialized), false);
  });
});

describe("searchHumorProviderCandidates callable", () => {
  const saved = {};
  let fake;

  before(() => {
    saved.emulator = process.env.FUNCTIONS_EMULATOR;
    saved.key = process.env.GIPHY_API_KEY;
    saved.fetch = globalThis.fetch;
    auth.addUser(ADMIN, {admin: true});
    auth.addUser(USER);
  });
  after(() => {
    for (const [name, value] of [["FUNCTIONS_EMULATOR", saved.emulator], ["GIPHY_API_KEY", saved.key]]) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    globalThis.fetch = saved.fetch;
  });
  beforeEach(() => {
    db.reset({});
    process.env.FUNCTIONS_EMULATOR = "true";
    process.env.GIPHY_API_KEY = FAKE_KEY;
    fake = fakeGiphyFetch({gifsByQuery: {"*": [FIXTURES.sitcomReaction, FIXTURES.landscape]}});
    globalThis.fetch = fake.fetchImpl;
  });

  it("is inert outside the emulator, even for an admin", async () => {
    delete process.env.FUNCTIONS_EMULATOR;
    await expectCode(callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["x"]}), "failed-precondition");
    process.env.FUNCTIONS_EMULATOR = "false";
    await expectCode(callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["x"]}), "failed-precondition");
    assert.equal(fake.calls.length, 0, "no provider call outside the emulator");
  });

  it("requires a signed-in admin", async () => {
    await expectCode(callAs(humor.searchHumorProviderCandidates, null, {queries: ["x"]}), "unauthenticated");
    await expectCode(callAs(humor.searchHumorProviderCandidates, USER, {queries: ["x"]}), "permission-denied");
    assert.equal(fake.calls.length, 0);
  });

  it("rejects invalid input", async () => {
    await expectCode(callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: []}), "invalid-argument");
  });

  it("returns candidates and writes nothing", async () => {
    const result = await callAs(humor.searchHumorProviderCandidates, ADMIN, {
      queries: ["sitcom reaction"],
      perQuery: 5,
      lang: "en",
      rating: "pg",
      dimension: "situational",
    });
    assert.equal(result.ok, true);
    assert.equal(result.configured, true);
    assert.deepEqual(result.candidates.map((c) => [c.giphyId, c.relevance.ok]), [
      ["sitcom01", true],
      ["land01", false],
    ]);
    assert.deepEqual(db.paths(), [], "the search wrote to Firestore");
    assert.equal(fake.calls.length, 1);
    assert.equal(fake.calls[0].searchParams.get("rating"), "pg");
    assert.equal(JSON.stringify(result).includes(FAKE_KEY), false);
  });

  it("answers 'not configured' without a key", async () => {
    delete process.env.GIPHY_API_KEY;
    const result = await callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["x"]});
    assert.deepEqual(result, {ok: false, configured: false});
  });

  it("binds the GIPHY secret and is exported only through the emulator-only gate", () => {
    const src = fs.readFileSync(path.join(__dirname, "..", "src", "humor", "index.ts"), "utf8");
    const start = src.indexOf("export const searchHumorProviderCandidates");
    assert.ok(start > 0);
    const options = src.slice(start, src.indexOf("async (request)", start));
    assert.match(options, /secrets:\s*\[giphyApiKey\]/);
    // Not a deployed function: index.ts never names it, and reaches it only
    // through emulatorOnly.ts, which it loads in the emulator process alone.
    const entry = fs.readFileSync(path.join(__dirname, "..", "src", "index.ts"), "utf8");
    assert.equal(entry.includes("searchHumorProviderCandidates"), false);
    const emulatorOnly = fs.readFileSync(path.join(__dirname, "..", "src", "emulatorOnly.ts"), "utf8");
    assert.match(emulatorOnly, /export \{searchHumorProviderCandidates\} from "\.\/humor\/index\.js"/);
  });
});

describe("curator tool (tool/humorCuratorSearch.cjs)", () => {
  const toolDir = path.join(__dirname, "..", "..", "tool");
  const tool = require(path.join(toolDir, "humorCuratorSearch.cjs"));
  const plan = JSON.parse(fs.readFileSync(path.join(toolDir, "humorCuratorQueryPlan.json"), "utf8"));

  it("knows exactly the humor dimensions the backend does", () => {
    assert.deepEqual([...tool.DIMENSIONS].sort(), [...HUMOR_CATEGORIES].sort());
  });

  it("ships a valid plan covering every dimension in Turkish and English", () => {
    assert.deepEqual(tool.planProblems(plan), []);
    for (const dimension of HUMOR_CATEGORIES) {
      for (const lang of ["tr", "en"]) {
        const group = plan.groups.find((g) => g.dimension === dimension && g.lang === lang);
        assert.ok(group, `no ${lang} group for ${dimension}`);
        assert.ok(group.queries.length >= 2, `${dimension}/${lang} has too few queries`);
      }
    }
    assert.ok(["g", "pg", "pg-13"].includes(plan.rating));
    for (const group of plan.groups) {
      assert.equal(parseProviderCandidateSearchInput({
        queries: group.queries, lang: group.lang, dimension: group.dimension,
        perQuery: plan.perQuery, rating: plan.rating,
      }).ok, true, `${group.dimension}/${group.lang} would be refused by the callable`);
    }
  });

  it("flags a bad plan", () => {
    assert.ok(tool.planProblems({groups: []}).length > 0);
    assert.ok(tool.planProblems({groups: [{dimension: "slapstick", lang: "tr", queries: ["a"]}]}).length > 0);
    assert.ok(tool.planProblems({groups: [{dimension: "dry", lang: "tr", queries: ["x".repeat(51)]}]}).length > 0);
  });

  it("only talks to loopback emulators", () => {
    const ok = tool.parseArgs(["--out", "c.json"]);
    assert.deepEqual(tool.argProblems(ok), []);
    assert.equal(ok.functionsHost, "127.0.0.1:5001");
    assert.equal(ok.authHost, "127.0.0.1:9099");
    for (const argv of [
      ["--out", "c.json", "--functions-host", "10.0.0.5:5001"],
      ["--out", "c.json", "--auth-host", "identitytoolkit.googleapis.com:443"],
      ["--functions-host", "127.0.0.1:27001"],
      ["--out", "c.json", "--rating", "r"],
      ["--out", "c.json", "--dimensions", "sarcasm,slapstick"],
      ["--out", "c.json", "--per-query", "80"],
    ]) {
      assert.ok(tool.argProblems(tool.parseArgs(argv)).length > 0, argv.join(" "));
    }
    assert.deepEqual(tool.argProblems(tool.parseArgs(["--print-plan"])), []);
  });

  it("downloads stills from GIPHY's CDN only", () => {
    assert.equal(
      tool.stillUrlOf({media: {stillUrl: "https://media1.giphy.com/media/a/200_s.gif"}}),
      "https://media1.giphy.com/media/a/200_s.gif",
    );
    assert.equal(
      tool.stillUrlOf({media: {stillUrl: "https://giphy.com.evil.tld/a.gif", stableStillUrl: "http://media.giphy.com/x.gif"}}),
      null,
    );
    assert.equal(
      tool.stillUrlOf({media: {stillUrl: null, stableStillUrl: "https://media.giphy.com/media/a/giphy_s.gif"}}),
      "https://media.giphy.com/media/a/giphy_s.gif",
    );
  });

  it("merges candidates across groups and escapes the contact sheet", () => {
    const byId = new Map();
    const c = {giphyId: "AbCd1234", queries: ["q1"], rank: 3, title: "<script>x</script>", relevance: {ok: true, basis: "lexicon"}, media: {}};
    tool.mergeCandidates(byId, {dimension: "dry", lang: "en"}, {candidates: [c, {giphyId: "../evil"}]});
    tool.mergeCandidates(byId, {dimension: "sarcasm", lang: "tr"}, {candidates: [{...c, queries: ["q2"], rank: 0}]});
    assert.deepEqual([...byId.keys()], ["AbCd1234"]);
    assert.deepEqual(byId.get("AbCd1234").foundBy, [
      {dimension: "dry", lang: "en", queries: ["q1"], rank: 3},
      {dimension: "sarcasm", lang: "tr", queries: ["q2"], rank: 0},
    ]);
    const html = tool.reviewHtml([...byId.values()]);
    assert.equal(html.includes("<script>x</script>"), false);
    assert.ok(html.includes("&lt;script&gt;"));
  });
});
