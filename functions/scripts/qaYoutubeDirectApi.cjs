const fs = require("fs");
const path = require("path");

function loadKey() {
  const envPath = path.join(__dirname, "..", ".env.mevora-d6ed0");
  if (fs.existsSync(envPath)) {
    const m = fs.readFileSync(envPath, "utf8").match(/^YOUTUBE_DATA_API_KEY=(.*)$/m);
    const v = m ? m[1].trim() : "";
    if (v && v !== "UNSET_PLACEHOLDER" && v.length >= 20) return v;
  }
  return null;
}

const QUERIES = [
  "komik",
  "türk komedi",
  "komik shorts",
  "türk mizah",
  "komik video",
  "absürt komedi",
  "kara mizah",
];

async function search(key, query) {
  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  url.searchParams.set("key", key);
  url.searchParams.set("part", "snippet");
  url.searchParams.set("type", "video");
  url.searchParams.set("q", query);
  url.searchParams.set("maxResults", "15");
  url.searchParams.set("safeSearch", "strict");
  url.searchParams.set("videoEmbeddable", "true");
  url.searchParams.set("videoSyndicated", "true");
  url.searchParams.set("videoDuration", "short");
  url.searchParams.set("relevanceLanguage", "tr");
  const res = await fetch(url);
  const body = await res.json().catch(() => ({}));
  return {status: res.status, body, query};
}

async function videos(key, ids) {
  const url = new URL("https://www.googleapis.com/youtube/v3/videos");
  url.searchParams.set("key", key);
  url.searchParams.set("part", "status,contentDetails,snippet");
  url.searchParams.set("id", ids.join(","));
  const res = await fetch(url);
  return {status: res.status, body: await res.json().catch(() => ({}))};
}

(async () => {
  const key = loadKey();
  if (!key) {
    console.log(JSON.stringify({phase: "direct_api", skipped: true, reason: "no_local_key"}));
    process.exit(0);
  }
  const seen = new Map();
  const searches = [];
  let quota = "OK";
  for (const q of QUERIES) {
    const r = await search(key, q);
    const reason = r.body?.error?.errors?.[0]?.reason;
    if (reason === "quotaExceeded" || reason === "dailyLimitExceeded") quota = "EXCEEDED";
    if (reason === "accessNotConfigured") {
      console.log(JSON.stringify({phase: "direct_api", apiEnabled: false, reason}));
      process.exit(0);
    }
    searches.push({
      query: q,
      httpStatus: r.status,
      count: (r.body.items || []).length,
      reason: reason || null,
      error: r.body?.error?.message || null,
      hasNext: !!r.body?.nextPageToken,
    });
    for (const item of r.body.items || []) {
      const id = item.id?.videoId;
      if (!id || seen.has(id)) continue;
      seen.set(id, {
        videoId: id,
        title: item.snippet?.title,
        channelId: item.snippet?.channelId,
        publishedAt: item.snippet?.publishedAt,
        thumb: item.snippet?.thumbnails?.high?.url || null,
        fromQuery: q,
      });
    }
    await new Promise((r) => setTimeout(r, 150));
  }
  const ids = [...seen.keys()];
  const detail = await videos(key, ids.slice(0, 50));
  let embeddable = 0,
    nonEmb = 0;
  for (const v of detail.body.items || []) {
    const row = seen.get(v.id);
    if (!row) continue;
    row.embeddable = v.status?.embeddable === true;
    row.duration = v.contentDetails?.duration || null;
    if (row.embeddable) embeddable++;
    else nonEmb++;
  }
  // pagination test
  const p1 = await search(key, "komik video");
  let paginationPass = false;
  if (p1.body?.nextPageToken) {
    const url = new URL("https://www.googleapis.com/youtube/v3/search");
    url.searchParams.set("key", key);
    url.searchParams.set("part", "snippet");
    url.searchParams.set("type", "video");
    url.searchParams.set("q", "komik video");
    url.searchParams.set("maxResults", "15");
    url.searchParams.set("safeSearch", "strict");
    url.searchParams.set("videoEmbeddable", "true");
    url.searchParams.set("videoSyndicated", "true");
    url.searchParams.set("videoDuration", "short");
    url.searchParams.set("relevanceLanguage", "tr");
    url.searchParams.set("pageToken", p1.body.nextPageToken);
    const p2 = await fetch(url);
    const b2 = await p2.json();
    const s1 = new Set((p1.body.items || []).map((i) => i.id?.videoId));
    paginationPass = (b2.items || []).some((i) => i.id?.videoId && !s1.has(i.id.videoId));
  }
  const player = [];
  for (const id of ids.slice(0, 5)) {
    const watch = `https://www.youtube.com/watch?v=${id}`;
    const o = await fetch(
      `https://www.youtube.com/oembed?url=${encodeURIComponent(watch)}&format=json`,
    );
    player.push({videoId: id, pass: o.ok, status: o.status});
  }
  console.log(
    JSON.stringify(
      {
        phase: "direct_api",
        apiEnabled: true,
        authOk: searches.some((s) => s.httpStatus === 200 && s.count > 0),
        quota,
        searches,
        totalUniqueResults: seen.size,
        embeddable,
        nonEmbeddable: nonEmb,
        pagination: {pass: paginationPass, hasNext: !!p1.body?.nextPageToken},
        playerTests: player,
        sampleIds: ids.slice(0, 10),
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
