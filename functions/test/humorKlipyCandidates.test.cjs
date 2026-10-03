const {describe, it, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");
const {FIXTURES, fakeGiphyFetch} = require("./helpers/giphyFixtures.cjs");
const {MEDIA, clip, searchText, fakeKlipyFetch} = require("./helpers/klipyFixtures.cjs");

/**
 * The curator's candidate search with a provider: `provider: "klipy"` returns
 * KLIPY clips (short videos), no provider still means GIPHY. Plus the KLIPY
 * mode of the dev tool that drives it and writes the review page.
 */
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

const humor = require("../lib/humor/index.js");
const {
  CANDIDATE_PROVIDERS,
  parseCandidateProvider,
  parseProviderCandidateSearchInput,
  searchKlipyClipCandidates,
} = require("../lib/humor/providerCandidates.js");
const {KlipyHumorSource} = require("../lib/humor/klipySource.js");

const KLIPY_KEY = "fixture-key-not-a-real-klipy-key";
const GIPHY_KEY = "fixture-key-not-a-real-giphy-key";
const ADMIN = "admin-curator";
const USER = "plain-user";

function input(overrides = {}) {
  const parsed = parseProviderCandidateSearchInput({queries: ["funny"], ...overrides});
  assert.equal(parsed.ok, true, JSON.stringify(parsed));
  return parsed.value;
}

function klipy(fetchOptions) {
  const fake = fakeKlipyFetch(fetchOptions);
  return {source: new KlipyHumorSource(KLIPY_KEY, {fetchImpl: fake.fetchImpl}), calls: fake.calls};
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    return true;
  });
}

describe("candidate search provider", () => {
  it("defaults to GIPHY and accepts exactly the known providers", () => {
    assert.deepEqual([...CANDIDATE_PROVIDERS], ["giphy", "klipy"]);
    for (const data of [undefined, null, {}, {queries: ["x"]}, {provider: null}, {provider: undefined}, []]) {
      assert.deepEqual(parseCandidateProvider(data), {ok: true, value: "giphy"}, JSON.stringify(data));
    }
    assert.deepEqual(parseCandidateProvider({provider: "giphy"}), {ok: true, value: "giphy"});
    assert.deepEqual(parseCandidateProvider({provider: "klipy"}), {ok: true, value: "klipy"});
    for (const provider of ["KLIPY", "tenor", "", 1, true, ["klipy"], {name: "klipy"}]) {
      assert.deepEqual(parseCandidateProvider({provider}), {ok: false, field: "provider"}, JSON.stringify(provider));
    }
  });
});

describe("searchKlipyClipCandidates", () => {
  it("returns each clip's own title, page, MP4 and preview", async () => {
    const {source} = klipy();
    const result = await searchKlipyClipCandidates(source, input({lang: "en", perQuery: 8}));
    assert.equal(result.provider, "klipy");
    assert.equal(result.contentFilter, "high");
    assert.deepEqual(result.counts, {received: 8, unique: 8});
    assert.deepEqual(result.rejected, {});
    assert.deepEqual(result.queries, [{query: "funny", received: 8, total: null, error: null}]);
    assert.deepEqual(result.candidates[0], {
      provider: "klipy",
      klipyId: "3102889768559058",
      proposedContentId: "hc_klipy_3102889768559058",
      queries: ["funny"],
      rank: 0,
      title: "Funny.",
      rawTitle: "Funny.",
      sourceUrl: "https://klipy.com/clips/funny-6",
      media: {
        mp4: {
          name: "mp4",
          url: "https://static.klipy.com/ii/48a9760ecdd5307ed701eb96ba85d319/94/ff/xJxQxk1o.mp4",
          sizeBytes: 101054,
          width: 1280,
          height: 538,
          mimeHint: "video/mp4",
        },
        poster: {
          name: "webp",
          url: "https://static.klipy.com/ii/48a9760ecdd5307ed701eb96ba85d319/94/ff/WFfPUII8.webp",
          sizeBytes: 16184,
          width: 320,
          height: 134,
          mimeHint: "image/webp",
        },
        width: 1280,
        height: 538,
        aspectRatio: 2.379,
      },
    });
    // The id past 2^53 arrives exact, and as a usable catalogue id.
    assert.equal(result.candidates[2].proposedContentId, "hc_klipy_9924056256405606");
    assert.ok(result.candidates.every((c) => /^[A-Za-z0-9_-]{1,128}$/.test(c.proposedContentId)));
  });

  it("merges a clip several queries returned and counts what it will not serve", async () => {
    const a = clip({id: "1000000000000001", title: "A"});
    const b = clip({id: "1000000000000002", title: "B"});
    const {source, calls} = klipy({
      textByQuery: {
        one: searchText([a, clip({type: "ad"})]),
        two: searchText([b, a, clip({id: "1000000000000003", file: {mp4: "https://evil.example/x.mp4"}})]),
      },
    });
    const result = await searchKlipyClipCandidates(source, input({queries: ["one", "two"], perQuery: 10, offset: 20}));
    assert.deepEqual(result.candidates.map((c) => [c.klipyId, c.queries, c.rank]), [
      ["1000000000000001", ["one", "two"], 20],
      ["1000000000000002", ["two"], 20],
    ]);
    assert.deepEqual(result.rejected, {"not-a-clip": 1, "missing-media": 1});
    assert.deepEqual(result.counts, {received: 5, unique: 2});
    // offset 20 at 10 per query is KLIPY's page 3.
    assert.deepEqual(calls.map((u) => [u.searchParams.get("q"), u.searchParams.get("page"), u.searchParams.get("per_page")]), [
      ["one", "3", "10"],
      ["two", "3", "10"],
    ]);
  });

  it("reports a failing query by status only and carries on", async () => {
    const {source} = klipy({status: 429});
    const result = await searchKlipyClipCandidates(source, input({queries: ["a", "b"]}));
    assert.deepEqual(result.queries.map((q) => q.error), ["klipy-http-429", "klipy-http-429"]);
    assert.deepEqual(result.candidates, []);
    const odd = {
      searchClipsRaw: async () => {
        throw new Error(`boom https://api.klipy.com/api/v1/${KLIPY_KEY}/clips/search`);
      },
    };
    const reduced = await searchKlipyClipCandidates(odd, input());
    assert.deepEqual(reduced.queries.map((q) => q.error), ["klipy-error"]);
    assert.equal(JSON.stringify(reduced).includes(KLIPY_KEY), false);
  });

  it("never returns the API key or a request URL", async () => {
    const {source} = klipy();
    const serialized = JSON.stringify(await searchKlipyClipCandidates(source, input()));
    assert.equal(serialized.includes(KLIPY_KEY), false);
    assert.equal(serialized.includes("api.klipy.com"), false);
  });
});

describe("searchHumorProviderCandidates callable — provider routing", () => {
  const saved = {};
  let giphy;
  let klipyFake;

  before(() => {
    for (const name of ["FUNCTIONS_EMULATOR", "GIPHY_API_KEY", "KLIPY_API_KEY"]) saved[name] = process.env[name];
    saved.fetch = globalThis.fetch;
    auth.addUser(ADMIN, {admin: true});
    auth.addUser(USER);
  });
  after(() => {
    for (const name of ["FUNCTIONS_EMULATOR", "GIPHY_API_KEY", "KLIPY_API_KEY"]) {
      if (saved[name] === undefined) delete process.env[name];
      else process.env[name] = saved[name];
    }
    globalThis.fetch = saved.fetch;
  });
  beforeEach(() => {
    db.reset({});
    process.env.FUNCTIONS_EMULATOR = "true";
    process.env.GIPHY_API_KEY = GIPHY_KEY;
    process.env.KLIPY_API_KEY = KLIPY_KEY;
    giphy = fakeGiphyFetch({gifsByQuery: {"*": [FIXTURES.sitcomReaction]}});
    klipyFake = fakeKlipyFetch();
    globalThis.fetch = async (url, init) =>
      (new URL(url).hostname === "api.klipy.com" ? klipyFake.fetchImpl : giphy.fetchImpl)(url, init);
  });

  it("searches GIPHY when no provider is given, exactly as before", async () => {
    const result = await callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["sitcom reaction"]});
    assert.equal(result.ok, true);
    assert.equal(result.provider, undefined);
    assert.deepEqual(result.candidates.map((c) => c.giphyId), ["sitcom01"]);
    assert.equal(giphy.calls.length, 1);
    assert.equal(klipyFake.calls.length, 0, "a GIPHY search must not call KLIPY");
  });

  it("searches GIPHY for provider \"giphy\"", async () => {
    const result = await callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["x"], provider: "giphy"});
    assert.deepEqual(result.candidates.map((c) => c.giphyId), ["sitcom01"]);
    assert.equal(klipyFake.calls.length, 0);
  });

  it("searches KLIPY clips for provider \"klipy\" and writes nothing", async () => {
    const result = await callAs(humor.searchHumorProviderCandidates, ADMIN, {
      queries: ["funny"],
      perQuery: 8,
      lang: "tr",
      provider: "klipy",
      dimension: "silly",
    });
    assert.equal(result.ok, true);
    assert.equal(result.configured, true);
    assert.equal(result.provider, "klipy");
    assert.equal(result.dimension, "silly");
    assert.equal(result.candidates.length, 8);
    assert.ok(result.candidates.every((c) => c.provider === "klipy" && c.media.mp4.url.startsWith("https://static.klipy.com/")));
    assert.deepEqual(db.paths(), [], "the search wrote to Firestore");
    assert.equal(giphy.calls.length, 0, "a KLIPY search must not call GIPHY");
    assert.equal(klipyFake.calls.length, 1);
    assert.equal(klipyFake.calls[0].searchParams.get("content_filter"), "high");
    assert.equal(klipyFake.calls[0].searchParams.get("locale"), "tr");
    const serialized = JSON.stringify(result);
    assert.equal(serialized.includes(KLIPY_KEY), false);
    assert.equal(serialized.includes(GIPHY_KEY), false);
  });

  it("rejects an unknown provider before calling anyone", async () => {
    await expectCode(
      callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["x"], provider: "tenor"}),
      "invalid-argument",
    );
    assert.equal(giphy.calls.length + klipyFake.calls.length, 0);
  });

  it("stays emulator-only and admin-only for KLIPY too", async () => {
    const data = {queries: ["x"], provider: "klipy"};
    await expectCode(callAs(humor.searchHumorProviderCandidates, null, data), "unauthenticated");
    await expectCode(callAs(humor.searchHumorProviderCandidates, USER, data), "permission-denied");
    delete process.env.FUNCTIONS_EMULATOR;
    await expectCode(callAs(humor.searchHumorProviderCandidates, ADMIN, data), "failed-precondition");
    assert.equal(klipyFake.calls.length, 0);
  });

  it("answers 'not configured' without a KLIPY key, even when GIPHY has one", async () => {
    delete process.env.KLIPY_API_KEY;
    const result = await callAs(humor.searchHumorProviderCandidates, ADMIN, {queries: ["x"], provider: "klipy"});
    assert.deepEqual(result, {ok: false, configured: false});
    assert.equal(giphy.calls.length + klipyFake.calls.length, 0);
  });

  it("binds the KLIPY secret next to the GIPHY one, and adds no new callable", () => {
    const src = fs.readFileSync(path.join(__dirname, "..", "src", "humor", "index.ts"), "utf8");
    const start = src.indexOf("export const searchHumorProviderCandidates");
    const options = src.slice(start, src.indexOf("async (request)", start));
    assert.match(options, /secrets:\s*\[giphyApiKey\]\.concat\(klipyApiKey \?\? \[\]\)/);
    assert.equal(/export const \w*[Kk]lipy\w*\s*=\s*onCall/.test(src), false);
    const emulatorOnly = fs.readFileSync(path.join(__dirname, "..", "src", "emulatorOnly.ts"), "utf8");
    assert.equal(/klipy/i.test(emulatorOnly.replace(/^\s*\/\/.*$/gm, "")), false, "no KLIPY export");
  });
});

describe("curator tool — KLIPY mode (tool/humorCuratorSearch.cjs)", () => {
  const tool = require(path.join(__dirname, "..", "..", "tool", "humorCuratorSearch.cjs"));
  const args = (...argv) => tool.parseArgs(argv);

  const candidate = (overrides = {}) => ({
    provider: "klipy",
    klipyId: "1000000000000001",
    proposedContentId: "hc_klipy_1000000000000001",
    queries: ["funny"],
    rank: 0,
    title: "A clip",
    rawTitle: "A clip",
    sourceUrl: "https://klipy.com/clips/a-clip",
    media: {
      mp4: {name: "mp4", url: `${MEDIA}/video.mp4`, sizeBytes: 204800, width: 1280, height: 536, mimeHint: "video/mp4"},
      poster: {name: "webp", url: `${MEDIA}/preview.webp`, sizeBytes: 40000, width: 320, height: 134, mimeHint: "image/webp"},
      width: 1280,
      height: 536,
      aspectRatio: 2.388,
    },
    ...overrides,
  });

  it("defaults to GIPHY and validates the provider", () => {
    assert.equal(args("--out", "x.json").provider, "giphy");
    assert.deepEqual(tool.argProblems(args("--out", "x.json", "--stills", "d")), []);
    assert.deepEqual(tool.argProblems(args("--provider", "klipy", "--out", "x.json", "--review", "d")), []);
    assert.ok(tool.argProblems(args("--provider", "tenor", "--out", "x.json")).some((p) => p.includes("--provider")));
  });

  it("downloads nothing in KLIPY mode and keeps GIPHY options out of it", () => {
    const problems = tool.argProblems(args("--provider", "klipy", "--out", "x.json", "--stills", "d", "--rating", "pg"));
    assert.ok(problems.some((p) => p.includes("--stills")));
    assert.ok(problems.some((p) => p.includes("--rating")));
    assert.ok(tool.argProblems(args("--out", "x.json", "--review", "d")).some((p) => p.includes("--review")));
  });

  it("budgets provider requests: one per query, 40 unless raised, never above 100", () => {
    assert.equal(tool.planRequestCount([{queries: ["a", "b"]}, {queries: ["c"]}]), 3);
    assert.equal(args("--provider", "klipy", "--out", "x.json").maxRequests, 40);
    for (const bad of ["0", "101", "x"]) {
      const problems = tool.argProblems(args("--provider", "klipy", "--out", "x.json", "--max-requests", bad));
      assert.ok(problems.some((p) => p.includes("--max-requests")), bad);
    }
    assert.deepEqual(tool.argProblems(args("--provider", "klipy", "--out", "x.json", "--max-requests", "100")), []);
  });

  it("loads review media from KLIPY's media hosts only", () => {
    assert.equal(tool.klipyMediaUrlOf(`${MEDIA}/video.mp4`), `${MEDIA}/video.mp4`);
    assert.equal(tool.klipyMediaUrlOf("https://static2.klipy.com/ii/a.mp4"), "https://static2.klipy.com/ii/a.mp4");
    for (const url of [
      "http://static.klipy.com/a.mp4",
      "https://static.klipy.com.evil.tld/a.mp4",
      "https://klipy.com/a.mp4",
      "https://x.static.klipy.com/a.mp4",
      "javascript:alert(1)",
      "",
      null,
    ]) {
      assert.equal(tool.klipyMediaUrlOf(url), null, String(url));
    }
  });

  it("merges clips across groups and drops one it could not play", () => {
    const byId = new Map();
    tool.mergeKlipyCandidates(byId, {dimension: "sarcasm", lang: "en"}, {
      candidates: [
        candidate(),
        candidate({klipyId: "1000000000000002", media: {mp4: {url: "https://evil.example/x.mp4"}}}),
        candidate({klipyId: "not-an-id"}),
      ],
    });
    tool.mergeKlipyCandidates(byId, {dimension: "dry", lang: "tr"}, {candidates: [candidate({queries: ["kuru"], rank: 4})]});
    assert.deepEqual([...byId.keys()], ["1000000000000001"]);
    assert.deepEqual(byId.get("1000000000000001").foundBy, [
      {dimension: "sarcasm", lang: "en", queries: ["funny"], rank: 0},
      {dimension: "dry", lang: "tr", queries: ["kuru"], rank: 4},
    ]);
  });

  it("writes a review page with on-demand muted videos, a checkbox each and an export button", () => {
    const byId = new Map();
    tool.mergeKlipyCandidates(byId, {dimension: "sarcasm", lang: "en"}, {
      candidates: [
        candidate({title: '<script>alert("x")</script>'}),
        candidate({klipyId: "1000000000000002", proposedContentId: "hc_klipy_1000000000000002", title: null, media: {
          mp4: {name: "mp4", url: `${MEDIA}/other.mp4`, sizeBytes: 100, width: 640, height: 360, mimeHint: "video/mp4"},
          poster: null, width: 640, height: 360, aspectRatio: 1.778,
        }}),
      ],
    });
    const html = tool.klipyReviewHtml([...byId.values()]);
    const videos = html.match(/<video [^>]*>/g) ?? [];
    assert.equal(videos.length, 2);
    for (const tag of videos) {
      assert.match(tag, / preload="none"/, "videos load on demand");
      assert.match(tag, / muted/);
      assert.match(tag, / controls/);
      assert.match(tag, / src="https:\/\/static\.klipy\.com\//);
    }
    assert.match(videos[0], / data-poster="https:\/\/static\.klipy\.com\/[^"]+preview\.webp"/);
    assert.equal(/data-poster/.test(videos[1]), false, "a clip without a preview has no poster");
    assert.equal((html.match(/<input type="checkbox" class="pick"/g) ?? []).length, 2);
    assert.match(html, /<button id="export"/);
    assert.match(html, /klipy-selection\.json/);
    assert.match(html, /200 KB/);
    assert.match(html, /1280×536/);
    assert.match(html, /KLIPY sayfası/);
    // Provider text is escaped in the markup and cannot close the data script.
    assert.equal(html.includes('<script>alert("x")</script>'), false);
    assert.match(html, /&lt;script&gt;alert\(&quot;x&quot;\)&lt;\/script&gt;/);
    const data = html.slice(html.indexOf('<script id="clips" type="application/json">'));
    const json = data.slice(data.indexOf(">") + 1, data.indexOf("</script>"));
    assert.equal(json.includes("<"), false);
    const records = JSON.parse(json);
    assert.deepEqual(records[0], {
      klipyId: "1000000000000001",
      contentId: "hc_klipy_1000000000000001",
      title: '<script>alert("x")</script>',
      sourceUrl: "https://klipy.com/clips/a-clip",
      downloadUrl: `${MEDIA}/video.mp4`,
      thumbUrl: `${MEDIA}/preview.webp`,
      width: 1280,
      height: 536,
      aspectRatio: 2.388,
      sizeBytes: 204800,
      foundBy: [{dimension: "sarcasm", lang: "en", queries: ["funny"], rank: 0}],
    });
    assert.equal(records[1].thumbUrl, null);
    // The export carries a measured duration, never a guessed one.
    assert.match(html, /durationMs: durations\[id\] \|\| null/);
    // The page stores nothing and talks to nobody but KLIPY's media hosts.
    assert.equal(/fetch\(|XMLHttpRequest|localStorage|indexedDB/.test(html), false);
  });

  it("leaves the GIPHY contact sheet as it was", () => {
    const byId = new Map();
    tool.mergeCandidates(byId, {dimension: "sarcasm", lang: "en"}, {
      candidates: [{giphyId: "AbCd1234", queries: ["q"], rank: 0, title: "T", relevance: {ok: true, basis: "lexicon"}, media: {}}],
    });
    const html = tool.reviewHtml([...byId.values()]);
    assert.match(html, /Humor curation candidates/);
    assert.equal(/<video|class="pick"|id="export"/.test(html), false);
  });
});
