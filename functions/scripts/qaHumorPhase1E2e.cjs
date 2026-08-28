/**
 * Faz 1 — Real Firebase + YouTube E2E (no mocks).
 * Writes tool/humor_e2e_live_ids.json for Flutter integration tests.
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT = "mevora-d6ed0";
const REGION = "europe-west1";
const ANDROID_APP_ID = "1:821220262229:android:1a12a39a06a7516f702fdc";
const WEB_API_KEY = "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw";
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");
const OUT_FILE = path.join(__dirname, "..", "..", "tool", "humor_e2e_live_ids.json");
const FIXTURE_FILE = path.join(
  __dirname,
  "..",
  "..",
  "integration_test",
  "fixtures",
  "humor_e2e_live_ids.json",
);

const YT_ID = /^[A-Za-z0-9_-]{11}$/;

async function exchangeAppCheck(debugToken) {
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/apps/${ANDROID_APP_ID}:exchangeDebugToken?key=${WEB_API_KEY}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({debugToken}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`appcheck ${resp.status} ${body.error?.message || ""}`);
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

async function call(name, idToken, appCheck, data = {}) {
  const resp = await fetch(`https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
      "X-Firebase-AppCheck": appCheck,
    },
    body: JSON.stringify({data}),
  });
  const body = await resp.json().catch(() => ({}));
  return {status: resp.status, result: body.result ?? body, error: body.error};
}

function extractVideoId(item) {
  const media = item.media || {};
  const embed = media.embedUrl || "";
  const m = String(embed).match(/youtube\.com\/embed\/([^?&/]+)/);
  if (m) return m[1];
  const cid = String(item.contentId || "");
  const m2 = cid.match(/ext_youtube_(.+)/);
  return m2 ? m2[1] : null;
}

function classify(item) {
  const prov = item.provider || "";
  const cid = String(item.contentId || "");
  const embed = String(item.media?.embedUrl || "");
  if (prov === "youtube" || cid.startsWith("ext_youtube_") || embed.includes("youtube.com/embed")) {
    return "youtube";
  }
  if (prov === "giphy" || cid.startsWith("ext_giphy_")) return "giphy";
  if (prov === "mevora-internal" || cid.startsWith("hc_")) return "internal";
  return "other";
}

(async () => {
  const report = {
    phase: "humor_phase1_e2e",
    timestamp: new Date().toISOString(),
    config: {
      USE_MOCK_HUMOR: false,
      HUMOR_LAB_ENABLED: "test via dart-define when running Flutter E2E",
      mockPath: "OFF",
      realPath: "ON",
    },
    firebaseCallable: {pass: false, httpStatus: null, error: null},
    youtubeApi: {pass: false, request: "SUCCESS"},
    feed: {page1: null, page2: null, paginationUnique: null, giphyCount: 0},
    rating: null,
    firestore: null,
    videoIds: [],
    items: [],
  };

  const debugToken = fs.readFileSync(TOKEN_FILE, "utf8").trim();
  const ac = await exchangeAppCheck(debugToken);
  const user = await signIn("qa_hour_a@mevora-qa.test", "QaHourly_a_2026!");

  const feed1 = await call("getHumorFeed", user.idToken, ac, {
    languages: ["tr", "en"],
    limit: 12,
  });
  report.firebaseCallable.httpStatus = feed1.status;
  report.firebaseCallable.error = feed1.error || null;
  const items1 = feed1.result?.items || [];
  const cursor = feed1.result?.nextCursor;

  const all1 = items1.map((item) => {
    const kind = classify(item);
    const videoId = kind === "youtube" ? extractVideoId(item) : null;
    return {
      contentId: item.contentId,
      provider: item.provider || kind,
      videoId,
      title: item.media?.textBody || null,
      thumbUrl: item.media?.thumbUrl || null,
      embedUrl: item.media?.embedUrl || null,
      kind,
    };
  });

  const giphy1 = all1.filter((i) => i.kind === "giphy").length;
  const yt1 = all1.filter((i) => i.kind === "youtube");
  const ids1 = yt1.map((i) => i.videoId).filter(Boolean);
  const valid1 = ids1.every((id) => YT_ID.test(id));

  report.feed.page1 = {
    httpStatus: feed1.status,
    count: items1.length,
    youtube: yt1.length,
    giphy: giphy1,
    internal: all1.filter((i) => i.kind === "internal").length,
    uniqueVideoIds: new Set(ids1).size,
    validVideoIds: valid1,
    hasCursor: !!cursor,
  };
  report.feed.giphyCount = giphy1;

  let items2 = [];
  let overlap = 0;
  if (cursor) {
    const feed2 = await call("getHumorFeed", user.idToken, ac, {
      languages: ["tr", "en"],
      limit: 12,
      cursor,
    });
    items2 = feed2.result?.items || [];
    const idsA = new Set(items1.map((i) => i.contentId));
    overlap = items2.filter((i) => idsA.has(i.contentId)).length;
    report.feed.page2 = {
      httpStatus: feed2.status,
      count: items2.length,
      overlapWithPage1: overlap,
    };
    report.feed.paginationUnique = overlap === 0 || items2.length === 0;
  }

  const passFeed =
    feed1.status === 200 &&
    yt1.length >= 5 &&
    valid1 &&
    new Set(ids1).size === ids1.length &&
    giphy1 === 0;

  report.firebaseCallable.pass = passFeed;
  report.youtubeApi.pass = passFeed && yt1.length >= 5;

  // Rating regression on first YouTube item
  const target = yt1[0];
  if (target) {
    const funny = await call("submitHumorFeedback", user.idToken, ac, {
      contentId: target.contentId,
      rating: "funny",
      dwellMs: 2500,
    });
    const notFunny = await call("submitHumorFeedback", user.idToken, ac, {
      contentId: target.contentId,
      rating: "not_funny",
      dwellMs: 900,
    });
    report.rating = {
      contentId: target.contentId,
      funnyStatus: funny.status,
      notFunnyStatus: notFunny.status,
      funnyOk: funny.status === 200 && funny.result?.ok === true,
      profileBuilding: notFunny.result?.profileBuilding,
      interactionCount: notFunny.result?.interactionCount,
    };

    try {
      if (admin.apps.length === 0) admin.initializeApp({projectId: PROJECT});
      const db = admin.firestore();
      const interaction = await db
        .doc(`users/${user.uid}/humorInteractions/${target.contentId}`)
        .get();
      const summary = await db.doc(`users/${user.uid}/humor/summary`).get();
      report.firestore = {
        interactionExists: interaction.exists,
        rating: interaction.data()?.rating || null,
        summaryExists: summary.exists,
        interactionCount: summary.data()?.interactionCount ?? null,
        funnyCount: summary.data()?.funnyCount ?? null,
        notFunnyCount: summary.data()?.notFunnyCount ?? null,
      };
    } catch (e) {
      report.firestore = {skipped: true, reason: String(e).slice(0, 120)};
    }
  }

  // Collect up to 20 unique video ids across pages for Flutter E2E
  const merged = [...items1, ...items2];
  const seen = new Set();
  const exportItems = [];
  for (const item of merged) {
    if (classify(item) !== "youtube") continue;
    const videoId = extractVideoId(item);
    if (!videoId || !YT_ID.test(videoId) || seen.has(videoId)) continue;
    seen.add(videoId);
    exportItems.push({
      contentId: item.contentId,
      videoId,
      embedUrl: item.media?.embedUrl,
      thumbUrl: item.media?.thumbUrl,
      provider: "youtube",
    });
    if (exportItems.length >= 20) break;
  }
  report.videoIds = exportItems.map((i) => i.videoId);
  report.items = exportItems;

  const payload = JSON.stringify({report, items: exportItems}, null, 2);
  fs.mkdirSync(path.dirname(OUT_FILE), {recursive: true});
  fs.writeFileSync(OUT_FILE, payload);
  fs.mkdirSync(path.dirname(FIXTURE_FILE), {recursive: true});
  fs.writeFileSync(FIXTURE_FILE, payload);

  console.log(JSON.stringify(report, null, 2));
  if (!passFeed) process.exit(1);
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
