const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT = "mevora-d6ed0";
const REGION = "europe-west1";
const ANDROID_APP_ID = "1:821220262229:android:1a12a39a06a7516f702fdc";
const WEB_API_KEY = "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw";
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");

async function exchangeAppCheck(debugToken) {
  const resp = await fetch(
    `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/apps/${ANDROID_APP_ID}:exchangeDebugToken?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({debugToken}),
    },
  );
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`appcheck ${resp.status}`);
  return body.token;
}

async function signIn(email, password) {
  const resp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({email, password, returnSecureToken: true}),
    },
  );
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new Error(`signin ${body.error?.message || resp.status}`);
  return {idToken: body.idToken, uid: body.localId};
}

async function call(name, idToken, ac, data) {
  const resp = await fetch(`https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
      "X-Firebase-AppCheck": ac,
    },
    body: JSON.stringify({data}),
  });
  const body = await resp.json().catch(() => ({}));
  return {status: resp.status, result: body.result ?? body, error: body.error};
}

(async () => {
  const ac = await exchangeAppCheck(fs.readFileSync(TOKEN_FILE, "utf8").trim());
  const user = await signIn("qa_hour_a@mevora-qa.test", "QaHourly_a_2026!");
  if (admin.apps.length === 0) admin.initializeApp({projectId: PROJECT});
  const db = admin.firestore();

  const feed = await call("getHumorFeed", user.idToken, ac, {
    languages: ["tr"],
    limit: 12,
  });
  const items = feed.result?.items || [];
  const yt = items.find(
    (i) =>
      i.provider === "youtube" ||
      String(i.contentId || "").startsWith("ext_youtube_"),
  );
  if (!yt) throw new Error("no_youtube_item_in_feed");
  const contentId = yt.contentId;

  const funny = await call("submitHumorFeedback", user.idToken, ac, {
    contentId,
    rating: "funny",
    dwellMs: 3200,
    replayCount: 0,
  });
  const neutral = await call("submitHumorFeedback", user.idToken, ac, {
    contentId,
    rating: "not_funny",
    dwellMs: 1100,
  });

  const interaction = await db
    .doc(`users/${user.uid}/humorInteractions/${contentId}`)
    .get();
  const summary = await db.doc(`users/${user.uid}/humor/summary`).get();

  // second feed should exclude rated item (seen filter)
  const feed2 = await call("getHumorFeed", user.idToken, ac, {
    languages: ["tr"],
    limit: 12,
  });
  const seenAgain = (feed2.result?.items || []).some((i) => i.contentId === contentId);

  console.log(
    JSON.stringify(
      {
        contentId,
        provider: yt.provider,
        funnyStatus: funny.status,
        funnyError: funny.error || null,
        notFunnyStatus: neutral.status,
        interaction: interaction.exists
          ? {
              rating: interaction.data()?.rating,
              reaction: interaction.data()?.reaction,
              provider: interaction.data()?.provider,
              category: interaction.data()?.category,
              hasTimestamp: !!interaction.data()?.timestamp,
            }
          : null,
        summary: summary.exists
          ? {
              interactionCount: summary.data()?.interactionCount,
              confidence: summary.data()?.confidence,
              version: summary.data()?.version,
            }
          : null,
        ratedItemResurfacedInNextFeed: seenAgain,
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
