/**
 * WYM Phase 7 — Humor TOP-3 ranking cases (dev live, controlled fixtures).
 * Does NOT change ranking architecture — only validates behavior.
 */
const path = require("path");
const {spawnSync} = require("child_process");

const PROJECT = process.env.WYM_E2E_PROJECT || "mevora-d6ed0";
const REGION = "europe-west1";
const BOOTSTRAP = path.join(__dirname, "..", "..", "tool", "qaBootstrapAdcFromFirebaseLogin.cjs");
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");
const OUT = path.join(__dirname, "..", "..", "tool", "whyYouMatchedPhase7HumorRankingEvidence.json");

const PROJECT_CONFIG = {
  "mevora-d6ed0": {
    androidAppId: "1:821220262229:android:1a12a39a06a7516f702fdc",
    apiKey: "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw",
  },
};

const QA_A = "test_wym_h7_a@mevora-qa.test";
const QA_B = "test_wym_h7_b@mevora-qa.test";
const PW = (l) => `TestWymH7_${l}_2026!`;
const HUMOR_Q = ["rq_002", "rq_005", "rq_008", "rq_011", "rq_014"];

function cfg() {
  return PROJECT_CONFIG[PROJECT];
}

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return;
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok) throw new Error("ADC bootstrap failed");
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
}

function humorVector(high = 82) {
  const dims = [
    "sarcasm", "absurd", "silly", "romantic", "dark", "meme", "dry", "wordplay",
    "situational", "cringe", "teasing", "wholesome", "intellectual", "physical",
  ];
  const v = {};
  for (const d of dims) v[d] = high;
  return v;
}

async function exchangeAppCheck(debugToken) {
  const {androidAppId, apiKey} = cfg();
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/apps/${androidAppId}:exchangeDebugToken?key=${apiKey}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({debugToken}),
  });
  const body = await resp.json();
  if (!resp.ok || !body.token) throw new Error("appcheck failed");
  return body.token;
}

async function signIn(email, password) {
  const {apiKey} = cfg();
  const resp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({email, password, returnSecureToken: true}),
    },
  );
  const body = await resp.json();
  if (!body.idToken) throw new Error(`signIn ${email}`);
  return body.idToken;
}

async function call(name, token, appCheck, data) {
  const url = `https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      "X-Firebase-AppCheck": appCheck,
    },
    body: JSON.stringify({data}),
  });
  const body = await resp.json();
  if (!resp.ok || body.error) throw new Error(JSON.stringify(body.error || body));
  return body.result ?? body;
}

async function ensureUser(auth, email, label) {
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, {password: PW(label), emailVerified: true});
  } catch {
    user = await auth.createUser({email, password: PW(label), emailVerified: true});
  }
  return user.uid;
}

async function seedMinimalHumor(db, FV, uidA, uidB, matchId, opts) {
  const {humorHigh, qaCount, vectorScore, confidence} = opts;
  for (const uid of [uidA, uidB]) {
    await db.doc(`profiles/${uid}`).set(
      {displayName: `H7_${uid.slice(0, 6)}`, profileCompleted: true, qaTag: "wym-phase7-humor"},
      {merge: true},
    );
    await db.doc(`users/${uid}/humor/summary`).set(
      {
        vector: humorVector(vectorScore),
        confidence,
        interactionCount: humorHigh ? 12 : 2,
        version: 1,
        updatedAt: FV.serverTimestamp(),
      },
      {merge: true},
    );
  }
  const pattern = Array(5).fill(false);
  for (let i = 0; i < qaCount; i++) pattern[i] = true;
  for (let i = 0; i < HUMOR_Q.length; i++) {
    const qid = HUMOR_Q[i];
    const match = pattern[i];
    await db.doc(`users/${uidA}/relationshipAnswers/${qid}`).set(
      {questionId: qid, answer: match ? "yes" : "no", updatedAt: FV.serverTimestamp()},
      {merge: true},
    );
    await db.doc(`users/${uidB}/relationshipAnswers/${qid}`).set(
      {questionId: qid, answer: match ? "yes" : "no", updatedAt: FV.serverTimestamp()},
      {merge: true},
    );
  }
  await db.doc(`matches/${matchId}`).set(
    {
      userIds: [uidA, uidB].sort(),
      isActive: true,
      createdAt: FV.serverTimestamp(),
      qaTag: "wym-phase7-humor",
    },
    {merge: true},
  );
}

async function runCase(admin, appCheck, label, opts, expectHumorInTop3) {
  const auth = admin.auth();
  const db = admin.firestore();
  const FV = admin.firestore.FieldValue;
  const emailA = `test_wym_h7_${label.toLowerCase()}_a@mevora-qa.test`;
  const emailB = `test_wym_h7_${label.toLowerCase()}_b@mevora-qa.test`;
  const uidA = await ensureUser(auth, emailA, `${label}A`);
  const uidB = await ensureUser(auth, emailB, `${label}B`);
  const matchId = [uidA, uidB].sort().join("_");
  await seedMinimalHumor(db, FV, uidA, uidB, matchId, opts);
  const token = await signIn(emailA, PW(`${label}A`));
  const resp = await call("getWhyYouMatched", token, appCheck, {matchId, forceRefresh: true});
  const humor = (resp.reasons || []).find((r) => r.category === "humor");
  const pass = expectHumorInTop3 ? !!humor : !humor;
  return {
    case: label,
    status: pass ? "PASS" : "FAIL",
    expectHumorInTop3,
    humorPresent: !!humor,
    reasonCount: resp.reasons?.length ?? 0,
    categories: (resp.reasons || []).map((r) => r.category),
    humor: humor
      ? {score: humor.score, confidence: humor.confidence, titleKey: humor.titleKey}
      : null,
    matchId,
  };
}

async function main() {
  ensureAdc();
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
  const debugToken = require("fs").readFileSync(TOKEN_FILE, "utf8").trim();
  const appCheck = await exchangeAppCheck(debugToken);

  const evidence = {
    phase: "wym-phase7-humor-ranking",
    project: PROJECT,
    cases: {},
    at: new Date().toISOString(),
  };

  evidence.cases.A = await runCase(
    admin,
    appCheck,
    "A",
    {humorHigh: true, qaCount: 5, vectorScore: 88, confidence: 0.6},
    true,
  );
  evidence.cases.B = await runCase(
    admin,
    appCheck,
    "B",
    {humorHigh: true, qaCount: 5, vectorScore: 88, confidence: 0.6},
    false,
  );
  evidence.cases.C = await runCase(
    admin,
    appCheck,
    "C",
    {humorHigh: true, qaCount: 1, vectorScore: 50, confidence: 0.5},
    false,
  );
  evidence.cases.D = await runCase(
    admin,
    appCheck,
    "D",
    {humorHigh: true, qaCount: 5, vectorScore: 50, confidence: 0.05},
    false,
  );

  const failed = Object.values(evidence.cases).filter((c) => c.status === "FAIL");
  evidence.final = failed.length === 0 ? "PASS" : "PARTIAL";
  require("fs").writeFileSync(OUT, JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
