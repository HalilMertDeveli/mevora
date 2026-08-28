/**
 * Humor Lab YouTube API health check — diagnostic only, never prints API keys.
 * Usage:
 *   set GOOGLE_APPLICATION_CREDENTIALS=...
 *   node scripts/qaYoutubeHumorHealth.cjs
 */
const fs = require("fs");
const path = require("path");
const {execSync} = require("child_process");
const admin = require("firebase-admin");

const PROJECT = "mevora-d6ed0";
const REGION = "europe-west1";
const ANDROID_APP_ID = "1:821220262229:android:1a12a39a06a7516f702fdc";
const WEB_API_KEY = "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw";
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");

const TR_QUERIES = [
  "komik",
  "türk komedi",
  "komik shorts",
  "türk mizah",
  "komik video",
  "absürt komedi",
  "kara mizah",
  "komik anlar",
  "meme",
  "hayvan komik",
];

const BUCKETS = [
  "turkish",
  "absurd",
  "meme",
  "animal",
  "fail",
];

function loadYoutubeKey() {
  // 1) env (emulator/local)
  const env = (process.env.YOUTUBE_DATA_API_KEY ?? "").trim();
  if (env && env !== "UNSET_PLACEHOLDER" && env.length >= 20) {
    return {source: "env", key: env};
  }
  // 2) Firebase Secret Manager via CLI (value never logged)
  try {
    const key = execSync(
      `firebase functions:secrets:access YOUTUBE_DATA_API_KEY --project ${PROJECT}`,
      {encoding: "utf8", stdio: ["pipe", "pipe", "pipe"]},
    ).trim();
    if (key && key !== "UNSET_PLACEHOLDER" && key.length >= 20) {
      return {source: "secret_manager", key};
    }
  } catch (e) {
    // access may fail locally even when Cloud Functions runtime has binding
  }
  // 3) Optional: gcloud with ADC
  try {
    const key = execSync(
      `gcloud secrets versions access latest --secret=YOUTUBE_DATA_API_KEY --project=${PROJECT}`,
      {
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
        env: {...process.env},
      },
    ).trim();
    if (key && key.length >= 20) return {source: "gcloud_adc", key};
  } catch {
    /* ignore */
  }
  return null;
}

async function youtubeSearch(key, query, lang = "tr", pageToken = null) {
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
  url.searchParams.set("relevanceLanguage", lang);
  if (pageToken) url.searchParams.set("pageToken", pageToken);

  const res = await fetch(url);
  const body = await res.json().catch(() => ({}));
  return {status: res.status, body, query};
}

async function youtubeVideosList(key, ids) {
  if (!ids.length) return {status: 200, body: {items: []}};
  const url = new URL("https://www.googleapis.com/youtube/v3/videos");
  url.searchParams.set("key", key);
  url.searchParams.set("part", "status,contentDetails,snippet");
  url.searchParams.set("id", ids.slice(0, 50).join(","));
  const res = await fetch(url);
  const body = await res.json().catch(() => ({}));
  return {status: res.status, body};
}

async function testOembed(videoId) {
  const watch = `https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`;
  const url = `https://www.youtube.com/oembed?url=${encodeURIComponent(watch)}&format=json`;
  try {
    const res = await fetch(url, {method: "GET"});
    return {ok: res.ok, status: res.status};
  } catch (e) {
    return {ok: false, status: 0, error: String(e).slice(0, 80)};
  }
}

async function exchangeAppCheck(debugToken) {
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/apps/${ANDROID_APP_ID}:exchangeDebugToken?key=${WEB_API_KEY}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({debugToken}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`appcheck ${resp.status}`);
  return body.token;
}

async function signIn(email, password) {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`signin ${body.error?.message || resp.status}`);
  return {idToken: body.idToken, uid: body.localId};
}

async function callFeed(idToken, appCheck, data = {}) {
  const resp = await fetch(`https://${REGION}-${PROJECT}.cloudfunctions.net/getHumorFeed`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
      "X-Firebase-AppCheck": appCheck,
    },
    body: JSON.stringify({data}),
  });
  const body = await resp.json().catch(() => ({}));
  return {status: resp.status, body, result: body.result ?? body, error: body.error};
}

function parseDuration(iso) {
  if (!iso) return null;
  const m = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!m) return null;
  return (
    Number(m[1] || 0) * 3600 + Number(m[2] || 0) * 60 + Number(m[3] || 0)
  );
}

async function main() {
  const report = {
    timestamp: new Date().toISOString(),
    project: PROJECT,
    secret: {exists: false, activeVersion: false, accessible: false, source: null},
    api: {enabled: null, authOk: false, httpStatus: null, error: null, quota: "UNKNOWN"},
    searches: [],
    allResults: [],
    embeddableStats: {embeddable: 0, nonEmbeddable: 0, unknown: 0},
    playerTests: [],
    feed: null,
    firestore: {},
    cache: {},
    pipeline: {},
  };

  // Secret metadata (no value) — CLI table may exit non-zero on Windows; treat stdout as signal
  try {
    const meta = execSync(
      `firebase functions:secrets:get YOUTUBE_DATA_API_KEY --project ${PROJECT}`,
      {encoding: "utf8", stdio: ["pipe", "pipe", "pipe"]},
    );
    report.secret.exists = /ENABLED/.test(meta);
    report.secret.activeVersion = /ENABLED/.test(meta);
  } catch (e) {
    const out = (e.stdout || e.stderr || "").toString();
    report.secret.exists = /ENABLED/.test(out);
    report.secret.activeVersion = /ENABLED/.test(out);
  }

  const keyInfo = loadYoutubeKey();
  if (!keyInfo) {
    report.secret.accessible = false;
    console.log(JSON.stringify({phase: "abort", reason: "YOUTUBE_DATA_API_KEY inaccessible", report}, null, 2));
    process.exit(1);
  }
  report.secret.accessible = true;
  report.secret.source = keyInfo.source;
  const key = keyInfo.key;

  // Direct API searches
  const seenIds = new Set();
  let quotaError = false;
  for (const query of TR_QUERIES) {
    const r = await youtubeSearch(key, query, "tr");
    const errReason = r.body?.error?.errors?.[0]?.reason;
    if (r.status === 403 && (errReason === "quotaExceeded" || errReason === "dailyLimitExceeded")) {
      quotaError = true;
      report.api.quota = "EXCEEDED";
      report.api.error = errReason;
    }
    if (r.status === 403 && errReason === "accessNotConfigured") {
      report.api.enabled = false;
      report.api.error = errReason;
    }
    const items = (r.body?.items ?? []).filter((i) => i.id?.videoId);
    report.searches.push({
      query,
      httpStatus: r.status,
      itemCount: items.length,
      error: r.body?.error?.message ?? null,
      reason: errReason ?? null,
      nextPageToken: r.body?.nextPageToken ? true : false,
    });
    for (const item of items) {
      const vid = item.id.videoId;
      if (seenIds.has(vid)) continue;
      seenIds.add(vid);
      report.allResults.push({
        videoId: vid,
        title: item.snippet?.title ?? null,
        channelId: item.snippet?.channelId ?? null,
        publishedAt: item.snippet?.publishedAt ?? null,
        thumbnail:
          item.snippet?.thumbnails?.high?.url ||
          item.snippet?.thumbnails?.medium?.url ||
          null,
        fromQuery: query,
      });
    }
    if (quotaError) break;
    await new Promise((r) => setTimeout(r, 200));
  }

  report.api.httpStatus = report.searches[0]?.httpStatus ?? null;
  report.api.authOk = report.searches.some((s) => s.httpStatus === 200 && s.itemCount > 0);
  if (!quotaError && report.api.authOk) report.api.quota = "OK";
  if (report.api.enabled === null) report.api.enabled = report.api.authOk;

  // videos.list for embeddable + duration
  const ids = report.allResults.map((r) => r.videoId);
  const details = await youtubeVideosList(key, ids);
  const detailMap = new Map();
  for (const v of details.body?.items ?? []) {
    detailMap.set(v.id, v);
  }
  for (const row of report.allResults) {
    const v = detailMap.get(row.videoId);
    if (!v) {
      row.embeddable = null;
      row.durationSec = null;
      report.embeddableStats.unknown += 1;
      continue;
    }
    row.embeddable = v.status?.embeddable === true;
    row.durationSec = parseDuration(v.contentDetails?.duration);
    row.channelId = v.snippet?.channelId ?? row.channelId;
    if (row.embeddable) report.embeddableStats.embeddable += 1;
    else report.embeddableStats.nonEmbeddable += 1;
  }

  // Player/oEmbed test on 5 distinct IDs
  const playerIds = report.allResults.slice(0, 5).map((r) => r.videoId);
  for (const vid of playerIds) {
    const o = await testOembed(vid);
    report.playerTests.push({videoId: vid, pass: o.ok, httpStatus: o.status});
  }

  // Pagination test on one query
  const pag = await youtubeSearch(key, "komik video", "tr");
  let paginationPass = false;
  if (pag.body?.nextPageToken) {
    const page2 = await youtubeSearch(key, "komik video", "tr", pag.body.nextPageToken);
    const ids1 = new Set((pag.body.items ?? []).map((i) => i.id?.videoId).filter(Boolean));
    const ids2 = (page2.body.items ?? []).map((i) => i.id?.videoId).filter(Boolean);
    paginationPass = ids2.some((id) => !ids1.has(id));
  }
  report.pagination = {pass: paginationPass, hasNextToken: !!pag.body?.nextPageToken};

  // Firestore: humorContent youtube items
  if (admin.apps.length === 0) admin.initializeApp({projectId: PROJECT});
  const db = admin.firestore();
  const ytContent = await db
    .collection("humorContent")
    .where("source.provider", "==", "youtube")
    .limit(100)
    .get()
    .catch(async () => {
      const snap = await db.collection("humorContent").limit(200).get();
      return {
        docs: snap.docs.filter((d) => d.data()?.source?.provider === "youtube"),
      };
    });
  const ytDocs = ytContent.docs ?? [];
  report.firestore.youtubeContentCount = ytDocs.length;
  report.firestore.youtubeActiveApproved = ytDocs.filter((d) => {
    const x = d.data();
    return x.active === true && x.safetyStatus === "approved";
  }).length;

  const cacheSnap = await db.collection("humorProviderCache").limit(50).get();
  report.cache.docCount = cacheSnap.size;
  report.cache.youtubeDocs = cacheSnap.docs.filter((d) => d.data()?.provider === "youtube").length;
  const cacheItems = [];
  for (const doc of cacheSnap.docs) {
    const d = doc.data();
    if (d.provider !== "youtube") continue;
    const expired = Number(d.expiresAtMs ?? 0) < Date.now();
    cacheItems.push({
      id: doc.id,
      queryKey: d.queryKey,
      itemCount: Array.isArray(d.items) ? d.items.length : 0,
      expired,
      ttlRemainingMin: expired ? 0 : Math.round((d.expiresAtMs - Date.now()) / 60000),
    });
  }
  report.cache.youtubeEntries = cacheItems;

  // getHumorFeed callable
  if (fs.existsSync(TOKEN_FILE)) {
    try {
      const ac = await exchangeAppCheck(fs.readFileSync(TOKEN_FILE, "utf8").trim());
      // Try QA hourly users first, then any test user pattern
      let user = null;
      for (const cred of [
        ["qa_hour_a@mevora-qa.test", "QaHourly_a_2026!"],
        ["qa_humor@test.mevora", "QaHumor_2026!"],
      ]) {
        try {
          user = await signIn(cred[0], cred[1]);
          break;
        } catch {
          /* next */
        }
      }
      if (user) {
        const feed1 = await callFeed(user.idToken, ac, {languages: ["tr", "en"], limit: 15});
        const items = feed1.result?.items ?? [];
        const byProvider = {};
        const youtubeItems = [];
        for (const item of items) {
          const prov =
            item.provider ||
            (String(item.contentId || "").includes("youtube") ? "youtube" : "unknown");
          byProvider[prov] = (byProvider[prov] || 0) + 1;
          const media = item.media ?? {};
          const embed = media.embedUrl || media.downloadUrl;
          const isYt =
            prov === "youtube" ||
            String(embed || "").includes("youtube.com/embed") ||
            String(item.contentId || "").startsWith("ext_youtube_");
          if (isYt) {
            youtubeItems.push({
              contentId: item.contentId,
              type: item.type,
              provider: prov,
              embedUrl: media.embedUrl ?? null,
              thumbUrl: media.thumbUrl ?? null,
              hasEmbed: !!media.embedUrl,
            });
          }
        }
        report.feed = {
          httpStatus: feed1.status,
          error: feed1.error ?? null,
          itemCount: items.length,
          byProvider,
          youtubeInFeed: youtubeItems.length,
          youtubeItems: youtubeItems.slice(0, 10),
          providersMeta: feed1.result?.providers ?? null,
        };

        // Second page cursor test
        const cursor = feed1.result?.nextCursor;
        if (cursor) {
          const feed2 = await callFeed(user.idToken, ac, {
            languages: ["tr", "en"],
            limit: 15,
            cursor,
          });
          const idsA = new Set(items.map((i) => i.contentId));
          const idsB = (feed2.result?.items ?? []).map((i) => i.contentId);
          report.feed.page2Unique = idsB.filter((id) => !idsA.has(id)).length;
        }
      } else {
        report.feed = {skipped: true, reason: "no_test_user_credentials"};
      }
    } catch (e) {
      report.feed = {error: String(e).slice(0, 200)};
    }
  } else {
    report.feed = {skipped: true, reason: "no_app_check_debug_token"};
  }

  // Pipeline estimate
  const afterValidation = report.allResults.filter((r) => r.videoId && r.title);
  const afterEmbeddable = afterValidation.filter((r) => r.embeddable !== false);
  report.pipeline = {
    youtubeApiResults: report.allResults.length,
    afterValidation: afterValidation.length,
    afterEmbeddableFilter: afterEmbeddable.length,
    afterModerationEstimate: afterEmbeddable.length,
    firestoreYoutubePool: report.firestore.youtubeActiveApproved,
    finalFeedYoutube: report.feed?.youtubeInFeed ?? null,
  };

  // Dedup check in API results
  const dupByQuery = {};
  for (const s of report.searches) {
    dupByQuery[s.query] = s.itemCount;
  }
  report.dedup = {
    uniqueVideoIdsFromApi: seenIds.size,
    totalRawAcrossQueries: report.searches.reduce((a, s) => a + s.itemCount, 0),
  };

  console.log(JSON.stringify({phase: "youtube_health", report}, null, 2));
}

main().catch((e) => {
  console.error(JSON.stringify({phase: "fatal", error: String(e)}));
  process.exit(1);
});
