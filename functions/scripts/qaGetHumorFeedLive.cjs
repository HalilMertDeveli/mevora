const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT = "mevora-d6ed0";
const REGION = "europe-west1";
const ANDROID_APP_ID = "1:821220262229:android:1a12a39a06a7516f702fdc";
const WEB_API_KEY = "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw";
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");

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
  return {status: resp.status, result: body.result ?? body, error: body.error};
}

function classifyItem(item) {
  const prov = item.provider || "";
  const cid = String(item.contentId || "");
  const media = item.media || {};
  const embed = String(media.embedUrl || "");
  const dl = String(media.downloadUrl || "");
  if (prov === "youtube" || cid.startsWith("ext_youtube_") || embed.includes("youtube.com/embed")) {
    return "youtube";
  }
  if (prov === "giphy" || cid.startsWith("ext_giphy_") || dl.includes("giphy.com")) {
    return "giphy";
  }
  if (prov === "mevora-internal" || cid.startsWith("hc_")) {
    return "internal";
  }
  return "other";
}

function extractVideoId(item) {
  const media = item.media || {};
  const embed = media.embedUrl || media.downloadUrl || "";
  const m = String(embed).match(/youtube\.com\/embed\/([^?&/]+)/);
  if (m) return m[1];
  const cid = String(item.contentId || "");
  const m2 = cid.match(/ext_youtube_(.+)/);
  return m2 ? m2[1] : null;
}

(async () => {
  const debugToken = fs.readFileSync(TOKEN_FILE, "utf8").trim();
  const ac = await exchangeAppCheck(debugToken);
  const user = await signIn("qa_hour_a@mevora-qa.test", "QaHourly_a_2026!");
  // interactions sample (optional — requires ADC/service account locally)
  let interactionsCount = null;
  let profileSummaryExists = null;
  let profileInteractionCount = null;
  try {
    if (admin.apps.length === 0) admin.initializeApp({projectId: PROJECT});
    const db = admin.firestore();
    const interactions = await db
      .collection(`users/${user.uid}/humorInteractions`)
      .limit(20)
      .get();
    const summary = await db.doc(`users/${user.uid}/humor/summary`).get();
    interactionsCount = interactions.size;
    profileSummaryExists = summary.exists;
    profileInteractionCount = summary.data()?.interactionCount ?? null;
  } catch (firestoreErr) {
    // Feed validation does not require Firestore ADC on developer machines.
  }

  const pages = [];
  let cursor = null;
  const allItems = [];
  for (let page = 0; page < 3; page++) {
    const feed = await callFeed(user.idToken, ac, {
      languages: ["tr", "en"],
      limit: 12,
      ...(cursor ? {cursor} : {}),
    });
    if (feed.error) {
      pages.push({page, status: feed.status, error: feed.error});
      break;
    }
    const items = feed.result?.items || [];
    pages.push({
      page,
      status: feed.status,
      count: items.length,
      providersMeta: feed.result?.providers || null,
      profileBuilding: feed.result?.profileBuilding,
    });
    allItems.push(...items);
    cursor = feed.result?.nextCursor;
    if (!cursor || items.length === 0) break;
  }

  const byProvider = {};
  const youtubeFeed = [];
  const seen = new Set();
  let dupes = 0;
  for (const item of allItems) {
    const kind = classifyItem(item);
    byProvider[kind] = (byProvider[kind] || 0) + 1;
    const vid = extractVideoId(item);
    const key = item.contentId;
    if (seen.has(key)) dupes++;
    seen.add(key);
    if (kind === "youtube") {
      youtubeFeed.push({
        contentId: item.contentId,
        videoId: vid,
        type: item.type,
        provider: item.provider,
        embedUrl: item.media?.embedUrl,
        thumbUrl: item.media?.thumbUrl,
        attribution: item.attributionRequired,
      });
    }
  }

  // oEmbed player probe for up to 5 youtube ids from feed
  const playerTests = [];
  for (const row of youtubeFeed.slice(0, 5)) {
    if (!row.videoId) {
      playerTests.push({videoId: null, pass: false, reason: "no_video_id"});
      continue;
    }
    const watch = `https://www.youtube.com/watch?v=${encodeURIComponent(row.videoId)}`;
    const url = `https://www.youtube.com/oembed?url=${encodeURIComponent(watch)}&format=json`;
    const res = await fetch(url);
    playerTests.push({videoId: row.videoId, pass: res.ok, httpStatus: res.status});
  }

  console.log(
    JSON.stringify(
      {
        uid: user.uid,
        pages,
        totalItems: allItems.length,
        uniqueItems: seen.size,
        duplicateCount: dupes,
        byProvider,
        youtubeInFeed: youtubeFeed.length,
        youtubeFeed,
        playerTests,
        interactionsCount,
        profileSummaryExists,
        profileInteractionCount,
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
