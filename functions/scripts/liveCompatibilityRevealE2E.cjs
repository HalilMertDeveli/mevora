/**
 * Live Firebase E2E for getMatchCompatibilityReveal (mevora-d6ed0).
 * Uses a temporary firebase-adminsdk key (.tmp-sa.json) to mint custom tokens.
 */
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "mevora-d6ed0";
const API_KEY = "AIzaSyDp7Xhe_89dAB2VEPxRiWSYMPVlr71_fIA";
const REGION = "europe-west1";
const CALLABLE =
  `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/getMatchCompatibilityReveal`;

const MATCH_ID =
  "CKLxiWTBtoXik888Wzqicqeuj6t2_F7CYZWNik3RGv3xQTZRLKWsMnTd2";
const PARTICIPANT_A = "CKLxiWTBtoXik888Wzqicqeuj6t2";
const PARTICIPANT_B = "F7CYZWNik3RGv3xQTZRLKWsMnTd2";
const INTRUDER = "MpOLRYKqPQQvGn1NsmSRqTvkGJw2";

const saPath = path.join(__dirname, "..", ".tmp-sa.json");
if (!fs.existsSync(saPath)) {
  throw new Error("Missing .tmp-sa.json — run createTmpSaKey.cjs first");
}
const sa = JSON.parse(fs.readFileSync(saPath, "utf8"));
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: PROJECT_ID,
  });
}

async function idTokenFor(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: custom, returnSecureToken: true}),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`token exchange failed: ${JSON.stringify(json)}`);
  }
  return json.idToken;
}

async function callReveal(idToken, matchId, appCheckToken) {
  const headers = {"Content-Type": "application/json"};
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  if (appCheckToken) headers["X-Firebase-AppCheck"] = appCheckToken;
  const res = await fetch(CALLABLE, {
    method: "POST",
    headers,
    body: JSON.stringify({data: {matchId}}),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = {raw: text};
  }
  return {status: res.status, json};
}

function summarize(label, result) {
  const err = result.json?.error;
  const data = result.json?.result ?? result.json?.data;
  return {
    label,
    httpStatus: result.status,
    errorStatus: err?.status || null,
    errorMessage: err?.message || null,
    available: data?.available ?? null,
    overallScore: data?.overallScore ?? null,
    isPremium: data?.isPremium ?? null,
    premiumRequired: data?.premiumRequired ?? null,
    pointCount: Array.isArray(data?.points) ? data.points.length : null,
    kinds: Array.isArray(data?.points) ? data.points.map((p) => p.kind) : null,
    messageKeys: Array.isArray(data?.points)
      ? data.points.map((p) => p.messageKey)
      : null,
    hasBreakdown: data?.breakdown != null,
    hasAnswerTextField: Array.isArray(data?.points)
      ? data.points.some(
          (p) =>
            Object.prototype.hasOwnProperty.call(p, "answerText") ||
            Object.prototype.hasOwnProperty.call(p, "answerId"),
        )
      : null,
    musicReason: Array.isArray(data?.points)
      ? data.points.some((p) => p.kind === "music")
      : null,
    questionReason: Array.isArray(data?.points)
      ? data.points.some((p) => p.kind === "questions")
      : null,
    rawKeys: data ? Object.keys(data) : null,
  };
}

async function main() {
  const results = [];
  results.push(summarize("unauthenticated", await callReveal(null, MATCH_ID)));

  const tokenA = await idTokenFor(PARTICIPANT_A);
  results.push(summarize("participant_a", await callReveal(tokenA, MATCH_ID)));

  const tokenIntruder = await idTokenFor(INTRUDER);
  results.push(
    summarize("non_participant", await callReveal(tokenIntruder, MATCH_ID)),
  );

  results.push(
    summarize("invalid_match", await callReveal(tokenA, "does-not-exist")),
  );

  const tokenB = await idTokenFor(PARTICIPANT_B);
  results.push(summarize("participant_b", await callReveal(tokenB, MATCH_ID)));

  // Premium entitlement snapshot for both participants.
  const db = admin.firestore();
  const premiumSnaps = {};
  for (const uid of [PARTICIPANT_A, PARTICIPANT_B]) {
    const user = await db.doc(`users/${uid}`).get();
    const sub = await db.doc(`users/${uid}/subscription/current`).get();
    premiumSnaps[uid] = {
      userPremiumFields: {
        isPremium: user.data()?.isPremium ?? null,
        premium: user.data()?.premium ?? null,
        subscriptionStatus: user.data()?.subscriptionStatus ?? null,
      },
      subscriptionDoc: sub.exists ? sub.data() : null,
    };
  }

  // Music / relationship presence checks (live facts).
  const musicA = await db.doc(`users/${PARTICIPANT_A}/music/summary`).get();
  const musicB = await db.doc(`users/${PARTICIPANT_B}/music/summary`).get();
  const relA = await db
    .doc(`users/${PARTICIPANT_A}/relationshipMatch/summary`)
    .get();
  const relB = await db
    .doc(`users/${PARTICIPANT_B}/relationshipMatch/summary`)
    .get();

  console.log(
    JSON.stringify(
      {
        matchId: MATCH_ID,
        liveFacts: {
          musicSummaryA: musicA.exists,
          musicSummaryB: musicB.exists,
          relationshipSummaryA: relA.exists,
          relationshipSummaryB: relB.exists,
          premiumSnaps,
        },
        results,
      },
      null,
      2,
    ),
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
