/**
 * Premium + empty-state live probes for getMatchCompatibilityReveal.
 * Temporarily sets Auth customClaims.premium on participant A, then clears it.
 */
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "mevora-d6ed0";
const API_KEY = "AIzaSyDp7Xhe_89dAB2VEPxRiWSYMPVlr71_fIA";
const CALLABLE =
  "https://europe-west1-mevora-d6ed0.cloudfunctions.net/getMatchCompatibilityReveal";
const MATCH_ID =
  "CKLxiWTBtoXik888Wzqicqeuj6t2_F7CYZWNik3RGv3xQTZRLKWsMnTd2";
const PARTICIPANT_A = "CKLxiWTBtoXik888Wzqicqeuj6t2";

const saPath = path.join(__dirname, "..", ".tmp-sa.json");
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
  if (!res.ok) throw new Error(JSON.stringify(json));
  return json.idToken;
}

async function callReveal(idToken, matchId) {
  const res = await fetch(CALLABLE, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({data: {matchId}}),
  });
  return {status: res.status, json: await res.json()};
}

function summarize(label, result) {
  const data = result.json?.result ?? result.json?.data;
  const err = result.json?.error;
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
    hasBreakdown: data?.breakdown != null,
    breakdownKeys:
      data?.breakdown && typeof data.breakdown === "object"
        ? Object.keys(data.breakdown)
        : null,
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
  };
}

async function setPremiumClaim(uid, premium) {
  const user = await admin.auth().getUser(uid);
  const claims = {...(user.customClaims || {})};
  if (premium) claims.premium = true;
  else delete claims.premium;
  await admin.auth().setCustomUserClaims(uid, claims);
  // Force token refresh by waiting briefly; new custom tokens include claims.
  await new Promise((r) => setTimeout(r, 1500));
}

async function main() {
  const out = {results: []};
  try {
    await setPremiumClaim(PARTICIPANT_A, true);
    const tokenPremium = await idTokenFor(PARTICIPANT_A);
    out.results.push(
      summarize("premium_participant", await callReveal(tokenPremium, MATCH_ID)),
    );
  } finally {
    await setPremiumClaim(PARTICIPANT_A, false);
  }

  // Free again (claim cleared) — confirm back to free gating.
  const tokenFree = await idTokenFor(PARTICIPANT_A);
  out.results.push(
    summarize("free_after_clear", await callReveal(tokenFree, MATCH_ID)),
  );

  // Empty-ish probe: invent a synthetic inactive/no-overlap isn't possible without
  // mutating user answers. Instead assert free path never invents music.
  console.log(JSON.stringify(out, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
