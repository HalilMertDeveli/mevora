/**
 * Phase 16 — YouTube API automated matrix (mocked fetch; no live quota burn).
 */
const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const {YoutubeHumorSource, mapYoutubeItem} = require(
  path.join(__dirname, "../lib/humor/youtubeSource.js"),
);
const {classifyProviderFetchError} = require(
  path.join(__dirname, "../lib/humor/providerOrchestrator.js"),
);

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() {
      return body;
    },
  };
}

describe("Phase 16 YouTube API matrix", () => {
  const originalFetch = global.fetch;
  let lastUrl = null;

  beforeEach(() => {
    lastUrl = null;
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it("API success returns normalized embeddable items", async () => {
    const urls = [];
    global.fetch = async (url) => {
      const u = String(url);
      urls.push(u);
      if (u.includes("/videos?")) {
        return jsonResponse(200, {
          items: [
            {
              id: "abcdefghijk",
              status: {embeddable: true},
            },
          ],
        });
      }
      return jsonResponse(200, {
        items: [
          {
            id: {videoId: "abcdefghijk"},
            snippet: {
              title: "Komik kısa",
              description: "test",
              channelTitle: "Komik Kanal",
              publishedAt: "2024-01-01T00:00:00Z",
              thumbnails: {
                high: {url: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg"},
              },
            },
          },
        ],
        nextPageToken: "NEXT",
      });
    };
    const src = new YoutubeHumorSource("test-key");
    const page = await src.searchByBucket({
      bucket: "meme",
      language: "tr",
      limit: 5,
    });
    assert.equal(page.normalized.length, 1);
    assert.equal(page.normalized[0].providerContentId, "abcdefghijk");
    assert.match(page.normalized[0].embedUrl, /youtube\.com\/embed\/abcdefghijk/);
    assert.equal(page.nextCursor, "NEXT");
    assert.ok(urls.some((u) => /videoEmbeddable=true/.test(u)));
    assert.ok(urls.some((u) => /\/videos\?/.test(u)));
  });

  it("non-embeddable videos.list status filters item out", async () => {
    global.fetch = async (url) => {
      if (String(url).includes("/videos?")) {
        return jsonResponse(200, {
          items: [{id: "abcdefghijk", status: {embeddable: false}}],
        });
      }
      return jsonResponse(200, {
        items: [
          {
            id: {videoId: "abcdefghijk"},
            snippet: {title: "Komik", description: "test"},
          },
        ],
      });
    };
    const src = new YoutubeHumorSource("k");
    const page = await src.searchByBucket({
      bucket: "meme",
      language: "tr",
      limit: 5,
    });
    assert.equal(page.normalized.length, 0);
  });

  it("API 401 maps to forbidden/invalid throw", async () => {
    global.fetch = async () =>
      jsonResponse(401, {
        error: {errors: [{reason: "keyInvalid"}], message: "bad key"},
      });
    const src = new YoutubeHumorSource("bad");
    await assert.rejects(
      () => src.search({query: "komik", language: "tr", limit: 3}),
      /youtube-keyInvalid|youtube-invalid|youtube-http-401/,
    );
  });

  it("API 403 forbidden maps to invalid-or-forbidden", async () => {
    global.fetch = async () =>
      jsonResponse(403, {
        error: {errors: [{reason: "forbidden"}], message: "denied"},
      });
    const src = new YoutubeHumorSource("k");
    await assert.rejects(
      () => src.search({query: "komik", language: "tr", limit: 3}),
      /youtube-invalid-or-forbidden:forbidden/,
    );
  });

  it("quotaExceeded maps to youtube-quotaExceeded", async () => {
    global.fetch = async () =>
      jsonResponse(403, {
        error: {errors: [{reason: "quotaExceeded"}]},
      });
    const src = new YoutubeHumorSource("k");
    await assert.rejects(
      () => src.search({query: "komik", language: "tr", limit: 3}),
      /youtube-quotaExceeded/,
    );
    assert.equal(
      classifyProviderFetchError("youtube-quotaExceeded"),
      "rate_limit",
    );
  });

  it("empty items throws youtube-empty via orchestrator path contract", async () => {
    global.fetch = async () => jsonResponse(200, {items: []});
    const src = new YoutubeHumorSource("k");
    const page = await src.searchByBucket({
      bucket: "fail",
      language: "tr",
      limit: 5,
    });
    assert.equal(page.normalized.length, 0);
    assert.equal(classifyProviderFetchError("youtube-empty"), "empty_result");
  });

  it("invalid video (missing videoId) is filtered out", () => {
    const mapped = mapYoutubeItem(
      {id: {}, snippet: {title: "no id"}},
      "tr",
      "meme",
    );
    assert.equal(mapped, null);
    const mapped2 = mapYoutubeItem(
      {id: {videoId: ""}, snippet: {title: "empty"}},
      "tr",
      "meme",
    );
    assert.equal(mapped2, null);
  });

  it("non-embeddable request is enforced via videoEmbeddable=true", async () => {
    global.fetch = async (url) => {
      lastUrl = String(url);
      return jsonResponse(200, {items: []});
    };
    const src = new YoutubeHumorSource("k");
    await src.search({query: "komik", language: "tr", limit: 2});
    assert.match(lastUrl, /videoEmbeddable=true/);
    assert.match(lastUrl, /videoSyndicated=true/);
    assert.equal(
      classifyProviderFetchError("embedding disabled"),
      "provider_unavailable",
    );
  });

  it("timeout/abort classifies as timeout", async () => {
    global.fetch = async () => {
      const err = new Error("The operation was aborted");
      err.name = "AbortError";
      throw err;
    };
    const src = new YoutubeHumorSource("k");
    await assert.rejects(
      () => src.search({query: "komik", language: "tr", limit: 2}),
      /abort|AbortError/i,
    );
    assert.equal(
      classifyProviderFetchError("AbortError: The operation was aborted"),
      "timeout",
    );
  });

  it("fallback chain continues after youtube failure classification", () => {
    const fs = require("fs");
    const src = fs.readFileSync(
      path.join(__dirname, "../src/humor/providerOrchestrator.ts"),
      "utf8",
    );
    const chainStart = src.indexOf("const chain: Array<{");
    const block = src.slice(chainStart, chainStart + 800);
    assert.ok(block.indexOf('provider: "youtube"') >= 0);
    assert.equal(block.indexOf('provider: "giphy"'), -1);
    assert.match(src, /catch \(err\)/);
    assert.match(src, /mevora-internal/);
  });
});
