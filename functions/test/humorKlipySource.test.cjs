const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const {RECORDED_SEARCH_TEXT, MEDIA, clip, searchText, fakeKlipyFetch} = require("./helpers/klipyFixtures.cjs");

/**
 * The KLIPY clips adapter: what one recorded search maps to, which media it
 * accepts, and that the key (which travels in the request URL) never leaves.
 */
const {
  KLIPY_CONTENT_FILTER,
  KLIPY_CUSTOMER_ID,
  KlipyHumorSource,
  MAX_KLIPY_MP4_BYTES,
  MAX_KLIPY_POSTER_BYTES,
  klipyIdOf,
  mapKlipyClip,
  parseKlipyJson,
  pickKlipyPoster,
  pickKlipyVideo,
} = require("../lib/humor/klipySource.js");
const {
  KLIPY_MEDIA_HOSTS,
  isAllowedMediaUrl,
  mediaUrlProblem,
  validateHumorSourceItem,
} = require("../lib/humor/contentValidation.js");

const FAKE_KEY = "fixture-key-not-a-real-klipy-key";

function source(fetchOptions) {
  const fake = fakeKlipyFetch(fetchOptions);
  return {source: new KlipyHumorSource(FAKE_KEY, {fetchImpl: fake.fetchImpl}), calls: fake.calls};
}

const recorded = () => parseKlipyJson(RECORDED_SEARCH_TEXT).data.data;

describe("KLIPY response parsing", () => {
  it("keeps every id exact, including one past 2^53", () => {
    const ids = recorded().map((c) => c.id);
    assert.equal(ids.length, 8);
    assert.ok(ids.every((id) => typeof id === "string"));
    // A real id past 2^53: no longer a safe integer for JSON.parse.
    assert.ok(ids.includes("9924056256405606"));
    assert.equal(Number.isSafeInteger(JSON.parse(RECORDED_SEARCH_TEXT).data.data[2].id), false);
    // What that costs: an odd id up there comes back as a different number.
    const odd = '{"data":{"data":[{"id":9924056256405607}]}}';
    assert.notEqual(String(JSON.parse(odd).data.data[0].id), "9924056256405607");
    assert.equal(parseKlipyJson(odd).data.data[0].id, "9924056256405607");
  });

  it("does not touch an \"id\" written inside a string value", () => {
    const body = parseKlipyJson('{"data":{"data":[{"id":12345678,"title":"say \\"id\\": 7 twice"}]}}');
    assert.deepEqual(body.data.data[0], {id: "12345678", title: 'say "id": 7 twice'});
  });

  it("refuses an id that is not a plain decimal, or already lost digits", () => {
    assert.equal(klipyIdOf({id: "3102889768559058"}), "3102889768559058");
    assert.equal(klipyIdOf({id: 3102889768559058}), "3102889768559058");
    for (const id of [undefined, null, "", "12ab", "12", 9924056256405606, 1.5, "../x"]) {
      assert.equal(klipyIdOf({id}), null, String(id));
    }
  });
});

describe("mapKlipyClip (recorded search)", () => {
  it("maps a clip to a video item with its own MP4, preview, title and credit", () => {
    const outcome = mapKlipyClip(recorded()[0], {language: "tr", query: "funny"});
    assert.equal(outcome.ok, true);
    assert.deepEqual(outcome.item, {
      sourceId: "3102889768559058",
      sourceUrl: "https://klipy.com/clips/funny-6",
      type: "video",
      language: "tr",
      title: "Funny.",
      rawTitle: "Funny.",
      slug: "funny-6--REDACTED",
      altText: null,
      rating: null,
      isSticker: false,
      tags: ["funny"],
      attribution: {
        provider: "klipy",
        displayName: null,
        username: null,
        sourceUrl: "https://klipy.com/clips/funny-6",
        verified: false,
      },
      query: "funny",
      queryCategory: null,
      origin: "clip",
      media: {
        downloadUrl: "https://static.klipy.com/ii/48a9760ecdd5307ed701eb96ba85d319/94/ff/xJxQxk1o.mp4",
        thumbUrl: "https://static.klipy.com/ii/48a9760ecdd5307ed701eb96ba85d319/94/ff/WFfPUII8.webp",
        previewUrl: null,
        durationMs: null,
        aspectRatio: 2.379,
        textBody: "Funny.",
        mimeHint: "video/mp4",
      },
    });
  });

  it("maps all eight recorded clips, each passing the content validation", () => {
    const items = recorded().map((raw) => mapKlipyClip(raw, {language: "en"}));
    assert.deepEqual(items.map((o) => o.ok), Array(8).fill(true));
    for (const {item} of items) {
      assert.deepEqual(validateHumorSourceItem(item), {ok: true}, item.sourceId);
      assert.equal(item.media.durationMs, null, "KLIPY sends no duration; none is invented");
      assert.equal(item.attribution.username, null, "KLIPY names no uploader");
    }
    assert.equal(new Set(items.map((o) => o.item.sourceId)).size, 8);
  });

  it("never invents a title", () => {
    for (const title of [null, "", "   ", "clip", "GIF"]) {
      const outcome = mapKlipyClip(clip({title}), {language: "en"});
      assert.equal(outcome.item.title, null, JSON.stringify(title));
      assert.equal(outcome.item.media.textBody, null);
    }
  });

  it("rejects what it cannot serve, naming why", () => {
    const reason = (raw) => {
      const outcome = mapKlipyClip(raw, {language: "en"});
      return outcome.ok ? "ok" : outcome.reason;
    };
    assert.equal(reason(null), "missing-id");
    assert.equal(reason(clip({type: "ad"})), "not-a-clip");
    assert.equal(reason(clip({id: "abc"})), "missing-id");
    assert.equal(reason(clip({file: {}})), "missing-media");
    assert.equal(reason(clip({file: {mp4: "http://static.klipy.com/ii/a/b/c/x.mp4"}})), "missing-media");
    assert.equal(reason(clip({file: {mp4: "https://evil.example/x.mp4"}})), "missing-media");
    assert.equal(reason(clip({file: {mp4: `${MEDIA}/preview.gif`}})), "missing-media");
    assert.equal(reason(clip({mp4: {width: 1280, height: 536}})), "unknown-media-size");
    assert.equal(reason(clip({mp4: {width: 1280, height: 536, size: MAX_KLIPY_MP4_BYTES + 1}})), "oversized-media");
    assert.equal(reason(clip({mp4: {width: 1280, height: 536, size: MAX_KLIPY_MP4_BYTES}})), "ok");
    assert.equal(reason(clip({mp4: {width: 1920, height: 1080, size: 1000}})), "resolution-too-high");
    assert.equal(reason(clip({mp4: {width: 720, height: 1280, size: 1000}})), "resolution-too-high");
  });
});

describe("KLIPY renditions", () => {
  it("accepts the one MP4 KLIPY sends, within the byte cap and 720p", () => {
    const choice = pickKlipyVideo(clip());
    assert.deepEqual(choice, {
      ok: true,
      rendition: {
        name: "mp4",
        url: `${MEDIA}/video.mp4`,
        sizeBytes: 200000,
        width: 1280,
        height: 536,
        mimeHint: "video/mp4",
      },
    });
    // The cap sits above every recorded clip (largest: 332 KB) with headroom.
    const sizes = recorded().map((c) => Number(c.file_meta.mp4.size));
    assert.ok(Math.max(...sizes) < MAX_KLIPY_MP4_BYTES / 4);
    assert.equal(MAX_KLIPY_MP4_BYTES, 1_500_000);
  });

  it("uses the clip's own WebP preview as poster, else its GIF, else none", () => {
    assert.equal(pickKlipyPoster(clip()).url, `${MEDIA}/preview.webp`);
    assert.equal(pickKlipyPoster(clip({file: {mp4: `${MEDIA}/video.mp4`, gif: `${MEDIA}/preview.gif`}})).name, "gif");
    assert.equal(
      pickKlipyPoster(clip({webp: {size: MAX_KLIPY_POSTER_BYTES + 1}})).name,
      "gif",
      "an oversized WebP falls back to the GIF",
    );
    assert.equal(pickKlipyPoster(clip({file: {mp4: `${MEDIA}/video.mp4`}})), null);
    assert.equal(
      pickKlipyPoster(clip({file: {mp4: `${MEDIA}/video.mp4`, webp: "https://evil.example/p.webp"}})),
      null,
      "a preview on another host is not a poster",
    );
    // A clip without a poster still maps: the player shows its loading state.
    const outcome = mapKlipyClip(clip({file: {mp4: `${MEDIA}/video.mp4`}}), {language: "en"});
    assert.equal(outcome.ok, true);
    assert.equal(outcome.item.media.thumbUrl, null);
    assert.deepEqual(validateHumorSourceItem(outcome.item), {ok: true});
  });
});

describe("media host allowlist", () => {
  it("allows exactly KLIPY's media hosts", () => {
    assert.deepEqual([...KLIPY_MEDIA_HOSTS], ["static.klipy.com", "static1.klipy.com", "static2.klipy.com"]);
    for (const host of KLIPY_MEDIA_HOSTS) {
      assert.equal(mediaUrlProblem(`https://${host}/ii/a/b/c/x.mp4`), null, host);
    }
  });

  it("rejects look-alikes, other KLIPY hosts and plain http", () => {
    const rejected = [
      "https://klipy.com/ii/a/x.mp4",
      "https://api.klipy.com/ii/a/x.mp4",
      "https://static3.klipy.com/ii/a/x.mp4",
      "https://static.klipy.com.evil.tld/ii/a/x.mp4",
      "https://klipy.com.evil.tld/x.mp4",
      "https://evilstatic.klipy.com/x.mp4",
      "https://notstatic.klipy.com/x.mp4",
      "https://static.klipy.co/x.mp4",
      "https://static-klipy.com/x.mp4",
      "https://evil.tld/static.klipy.com/x.mp4",
      "https://evil.tld/?h=static.klipy.com",
      "https://static.klipy.com@evil.tld/x.mp4",
    ];
    for (const url of rejected) {
      assert.equal(mediaUrlProblem(url), "host-not-allowed", url);
      assert.equal(isAllowedMediaUrl(url), false, url);
    }
    assert.equal(mediaUrlProblem("http://static.klipy.com/ii/a/x.mp4"), "insecure-url");
  });

  it("leaves GIPHY and Storage exactly as they were", () => {
    assert.equal(mediaUrlProblem("https://media1.giphy.com/media/abc/giphy.webp"), null);
    assert.equal(mediaUrlProblem("https://firebasestorage.googleapis.com/v0/b/x/o/y"), null);
    assert.equal(mediaUrlProblem("https://giphy.com.attacker.tld/x.gif"), "host-not-allowed");
  });
});

describe("KlipyHumorSource", () => {
  it("asks for clips with the strictest filter and a fixed, non-personal customer id", async () => {
    const {source: klipy, calls} = source();
    const result = await klipy.searchClips({query: "komik tepki", language: "tr", limit: 3, page: 2});
    assert.equal(result.items.length, 8);
    assert.deepEqual(result.rejected, {});
    assert.equal(result.hasNext, true);
    assert.equal(calls.length, 1);
    const url = calls[0];
    assert.equal(url.origin, "https://api.klipy.com");
    assert.equal(url.pathname, `/api/v1/${FAKE_KEY}/clips/search`);
    assert.deepEqual(Object.fromEntries(url.searchParams), {
      q: "komik tepki",
      page: "2",
      per_page: "8", // the endpoint's minimum
      customer_id: KLIPY_CUSTOMER_ID,
      locale: "tr",
      content_filter: KLIPY_CONTENT_FILTER,
    });
    assert.equal(KLIPY_CONTENT_FILTER, "high");
    assert.equal(KLIPY_CUSTOMER_ID, "mevora-curator");
  });

  it("maps English to the US locale and caps a page at 50", async () => {
    const {source: klipy, calls} = source();
    await klipy.searchClips({query: "x", language: "en", limit: 500});
    assert.equal(calls[0].searchParams.get("locale"), "us");
    assert.equal(calls[0].searchParams.get("per_page"), "50");
    assert.equal(calls[0].searchParams.get("page"), "1");
  });

  it("counts results it will not serve instead of returning them", async () => {
    const text = searchText([clip({id: "1000000000000001"}), clip({type: "ad"}), clip({id: "1000000000000002", file: {}})]);
    const {source: klipy} = source({textByQuery: {"*": text}});
    const result = await klipy.searchClips({query: "x", language: "en", limit: 8});
    assert.deepEqual(result.items.map((i) => i.sourceId), ["1000000000000001"]);
    assert.deepEqual(result.rejected, {"not-a-clip": 1, "missing-media": 1});
    assert.equal(result.received, 3);
  });

  it("fails with a status-only message that never holds the key or the URL", async () => {
    const cases = [
      [{status: 404}, "klipy-http-404"],
      [{status: 429}, "klipy-http-429"],
      [{textByQuery: {"*": "<html>not json"}}, "klipy-bad-json"],
      [{textByQuery: {"*": '{"result":false,"errors":{"message":["nope"]}}'}}, "klipy-rejected"],
    ];
    for (const [options, expected] of cases) {
      const {source: klipy} = source(options);
      await assert.rejects(klipy.searchClipsRaw({query: "x", language: "en", limit: 8}), (error) => {
        assert.equal(error.message, expected);
        assert.equal(String(error.stack).includes(FAKE_KEY), false);
        assert.equal(/klipy\.com/.test(error.message), false);
        return true;
      });
    }
    const throwing = new KlipyHumorSource(FAKE_KEY, {
      fetchImpl: async (url) => {
        throw new Error(`connect failed for ${url}`);
      },
    });
    await assert.rejects(throwing.searchClipsRaw({query: "x", language: "en", limit: 8}), (error) => {
      assert.equal(error.message, "klipy-network-error");
      assert.equal(String(error.stack).includes(FAKE_KEY), false);
      return true;
    });
  });

  it("pages through the provider-agnostic interface and serves no images", async () => {
    const {source: klipy, calls} = source();
    const first = await klipy.search({query: "funny", language: "en", limit: 8});
    assert.equal(first.items.length, 8);
    assert.ok(first.nextCursor);
    await klipy.getNextPage(first.nextCursor);
    assert.equal(calls[1].searchParams.get("page"), "2");
    assert.equal(calls[1].searchParams.get("q"), "funny");
    assert.deepEqual(await klipy.getImages(), {items: [], nextCursor: null});
    assert.deepEqual(await klipy.getNextPage("not-a-cursor"), {items: [], nextCursor: null});
    assert.equal(JSON.stringify(first).includes(FAKE_KEY), false);
  });

  it("is not created without a key", () => {
    const saved = process.env.KLIPY_API_KEY;
    delete process.env.KLIPY_API_KEY;
    try {
      assert.equal(KlipyHumorSource.tryCreate(), null);
      process.env.KLIPY_API_KEY = "   ";
      assert.equal(KlipyHumorSource.tryCreate(), null);
      process.env.KLIPY_API_KEY = FAKE_KEY;
      assert.ok(KlipyHumorSource.tryCreate() instanceof KlipyHumorSource);
    } finally {
      if (saved === undefined) delete process.env.KLIPY_API_KEY;
      else process.env.KLIPY_API_KEY = saved;
    }
  });
});

describe("KLIPY key hygiene", () => {
  const FUNCTIONS_DIR = path.join(__dirname, "..");

  it("declares the KLIPY secret inside the emulator only, so a deploy never asks for it", () => {
    const probe = (emulator) => {
      const env = {...process.env};
      delete env.FUNCTIONS_EMULATOR;
      delete env.KLIPY_API_KEY;
      if (emulator) env.FUNCTIONS_EMULATOR = "true";
      const run = spawnSync(
        process.execPath,
        ["-e", "const c = require('./lib/humor/humorApiConfig.js'); process.stdout.write(JSON.stringify({declared: c.klipyApiKey !== null, name: c.klipyApiKey ? c.klipyApiKey.name : null, configured: c.isKlipyConfigured()}));"],
        {cwd: FUNCTIONS_DIR, env, encoding: "utf8"},
      );
      assert.equal(run.status, 0, run.stderr);
      return JSON.parse(run.stdout);
    };
    assert.deepEqual(probe(false), {declared: false, name: null, configured: false});
    assert.deepEqual(probe(true), {declared: true, name: "KLIPY_API_KEY", configured: false});
  });

  it("is not part of the provider sync", () => {
    const ingest = fs.readFileSync(path.join(FUNCTIONS_DIR, "src", "humor", "ingest.ts"), "utf8");
    assert.equal(/klipy/i.test(ingest), false, "KLIPY must not be synced automatically");
  });

  it("keeps real keys out of the KLIPY fixtures and tests", () => {
    const files = [
      path.join(__dirname, "helpers", "klipyFixtures.cjs"),
      ...fs.readdirSync(__dirname).filter((name) => /^humorKlipy.*\.test\.cjs$/.test(name)).map((name) => path.join(__dirname, name)),
    ];
    assert.ok(files.length >= 2);
    for (const file of files) {
      const text = fs.readFileSync(file, "utf8");
      // The key travels in the URL path: no recorded request URL may appear.
      assert.equal(/api\.klipy\.com\/api\/v1\/[A-Za-z0-9]{20,}/.test(text), false, file);
      // No long opaque token outside media URLs and the redacted previews.
      const stripped = text
        .replace(/https:(?:\\?\/){2}[^\s"'`]+/g, "")
        .replace(/[0-9a-f]{32}/g, "");
      const tokens = stripped.match(/[A-Za-z0-9]{40,}/g) ?? [];
      assert.deepEqual(tokens, [], file);
      // No dotenv-style line carrying a value.
      assert.equal(/^\s*KLIPY_API_KEY=\S/m.test(text), false, file);
    }
  });
});
