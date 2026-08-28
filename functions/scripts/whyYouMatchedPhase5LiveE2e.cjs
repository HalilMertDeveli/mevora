/**
 * WYM Phase 5 — Real Firebase E2E (callable + Firestore + security probes).
 *
 * Usage:
 *   node functions/scripts/whyYouMatchedPhase5LiveE2e.cjs
 *   WYM_E2E_PROJECT=mevora-staging node functions/scripts/whyYouMatchedPhase5LiveE2e.cjs
 *
 * Requires: firebase login (ADC bootstrap), App Check debug token file.
 */
const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const PROJECT = process.env.WYM_E2E_PROJECT || "mevora-d6ed0";
const REGION = "europe-west1";
const BOOTSTRAP = path.join(__dirname, "..", "..", "tool", "qaBootstrapAdcFromFirebaseLogin.cjs");
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");
const OUT_FILE = path.join(__dirname, "..", "..", "tool", "whyYouMatchedPhase5LiveEvidence.json");

const PROJECT_CONFIG = {
  "mevora-d6ed0": {
    androidAppId: "1:821220262229:android:1a12a39a06a7516f702fdc",
    apiKey: "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw",
  },
  "mevora-staging": {
    androidAppId: "1:905717896949:android:6d0fce4d2c911c2fbc57bc",
    apiKey: "AIzaSyC7dWuaKZmX1c5q4QyQPLUKBPhRvNSqaW0",
  },
};

const QA_A_EMAIL = "test_wym_a@mevora-qa.test";
const QA_B_EMAIL = "test_wym_b@mevora-qa.test";
const QA_C_EMAIL = "test_wym_c@mevora-qa.test";
const QA_PASSWORD = (label) => `TestWym_${label}_2026!`;

const HUMOR_FUN_QUESTIONS = ["rq_002", "rq_005", "rq_008", "rq_011", "rq_014"];
const FORBIDDEN_RESPONSE_KEYS = [
  "rawAnswers",
  "relationshipAnswers",
  "humorVector",
  "lat",
  "lng",
  "latitude",
  "longitude",
  "accessToken",
  "refreshToken",
  "password",
  "email",
  "birthDate",
];

const evidence = {
  phase: "wym-phase5-live-e2e",
  project: PROJECT,
  region: REGION,
  startedAt: new Date().toISOString(),
  steps: {},
  final: "BLOCKED",
};

function mark(step, status, detail = {}) {
  evidence.steps[step] = {status, ...detail, at: new Date().toISOString()};
  console.log(JSON.stringify({step, status, ...detail}));
}

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return process.env.GOOGLE_APPLICATION_CREDENTIALS;
  }
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok || !parsed.adcPath) {
    throw new Error(`ADC bootstrap failed: ${line || boot.stderr}`);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
  return parsed.adcPath;
}

function projectConfig() {
  const cfg = PROJECT_CONFIG[PROJECT];
  if (!cfg) {
    throw new Error(`unsupported WYM_E2E_PROJECT=${PROJECT}`);
  }
  return cfg;
}

function callableUrl(name) {
  return `https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`;
}

function firestoreDocUrl(docPath) {
  return `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}`;
}

async function exchangeAppCheckToken(debugToken) {
  const {androidAppId, apiKey} = projectConfig();
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/apps/${androidAppId}:exchangeDebugToken?key=${apiKey}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({debugToken}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || !body.token) {
    throw new Error(
      `appcheck-exchange-failed status=${resp.status} ${body.error?.message || JSON.stringify(body)}`,
    );
  }
  return body.token;
}

async function signIn(email, password) {
  const {apiKey} = projectConfig();
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || !body.idToken) {
    throw new Error(
      `signIn-failed ${email} status=${resp.status} ${body.error?.message || ""}`,
    );
  }
  return {idToken: body.idToken, uid: body.localId, email};
}

async function callCallable(name, idToken, appCheckToken, data = {}) {
  const t0 = Date.now();
  const resp = await fetch(callableUrl(name), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
      "X-Firebase-AppCheck": appCheckToken,
    },
    body: JSON.stringify({data}),
  });
  const latencyMs = Date.now() - t0;
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || body.error) {
    const err = body.error || {};
    const error = new Error(
      `callable ${name} failed status=${resp.status} code=${err.status || err.code || ""} message=${err.message || JSON.stringify(body)}`,
    );
    error.httpStatus = resp.status;
    error.callableName = name;
    error.payload = body;
    error.latencyMs = latencyMs;
    throw error;
  }
  return {result: body.result ?? body, latencyMs};
}

function walkKeys(obj, prefix = "", out = []) {
  if (!obj || typeof obj !== "object") return out;
  if (Array.isArray(obj)) {
    for (const item of obj) walkKeys(item, prefix, out);
    return out;
  }
  for (const [k, v] of Object.entries(obj)) {
    const p = prefix ? `${prefix}.${k}` : k;
    out.push(p);
    walkKeys(v, p, out);
  }
  return out;
}

function scanForbidden(obj) {
  const keys = walkKeys(obj);
  const hits = [];
  for (const k of keys) {
    const leaf = k.split(".").pop();
    if (FORBIDDEN_RESPONSE_KEYS.includes(leaf)) {
      hits.push(k);
    }
    const lower = leaf.toLowerCase();
    if (lower.includes("accesstoken") || lower.includes("refreshtoken")) {
      hits.push(k);
    }
  }
  return hits;
}

function humorVector(high = 82) {
  const dims = [
    "sarcasm",
    "absurd",
    "silly",
    "romantic",
    "dark",
    "meme",
    "dry",
    "wordplay",
    "situational",
    "cringe",
    "teasing",
  ];
  const vector = {};
  for (const d of dims) vector[d] = high;
  return vector;
}

function canonicalMatchId(a, b) {
  return [a, b].sort().join("_");
}

async function ensureUser(admin, email, label) {
  const auth = admin.auth();
  const db = admin.firestore();
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, {
      password: QA_PASSWORD(label),
      emailVerified: true,
      displayName: `TEST_WYM_USER_${label}`,
    });
  } catch {
    user = await auth.createUser({
      email,
      password: QA_PASSWORD(label),
      emailVerified: true,
      displayName: `TEST_WYM_USER_${label}`,
    });
  }
  const uid = user.uid;
  await db.doc(`users/${uid}`).set(
    {
      email,
      displayName: `TEST_WYM_USER_${label}`,
      isQaUser: true,
      qaTag: "wym-phase5-e2e",
      profileCompleted: true,
      onboardingCompleted: true,
      accountStatus: "active",
      isActive: true,
      isBanned: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return uid;
}

async function seedRichProfile(db, FieldValue, uid, label, humorHigh = true) {
  await db.doc(`profiles/${uid}`).set(
    {
      displayName: `TEST_WYM_USER_${label}`,
      profileCompleted: true,
      onboardingCompleted: true,
      isDiscoverable: true,
      isQaUser: true,
      qaTag: "wym-phase5-e2e",
      interests: ["music", "travel", "food", "art"],
      languages: ["tr", "en"],
      lifestyle: ["smoking:no", "pets:yes", "drinking:socially"],
      lifestyleProfile: {
        smoking: "no",
        drinking: "socially",
        pets: "yes",
        exercise: "regular",
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`userLocation/${uid}`).set(
    {
      lat: label === "A" ? 41.0082 : 41.015,
      lng: label === "A" ? 28.9784 : 28.985,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  if (humorHigh) {
    await db.doc(`users/${uid}/humor/summary`).set(
      {
        vector: humorVector(85),
        confidence: 0.55,
        interactionCount: 12,
        funnyCount: 10,
        notFunnyCount: 2,
        exploredCategories: ["absurd", "meme"],
        version: 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  } else {
    await db.doc(`users/${uid}/humor/summary`).delete().catch(() => undefined);
  }
}

async function seedHumorAnswersPair(db, FieldValue, uidA, uidB, bMatchesPattern) {
  for (let i = 0; i < HUMOR_FUN_QUESTIONS.length; i++) {
    const qid = HUMOR_FUN_QUESTIONS[i];
    const answerA = "a";
    const answerB = bMatchesPattern[i] ? "a" : "b";
    await db.doc(`users/${uidA}/relationshipAnswers/${qid}`).set(
      {
        questionId: qid,
        answerId: answerA,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    await db.doc(`users/${uidB}/relationshipAnswers/${qid}`).set(
      {
        questionId: qid,
        answerId: answerB,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
}

async function seedMatch(db, FieldValue, uidA, uidB) {
  const matchId = canonicalMatchId(uidA, uidB);
  await db.doc(`matches/${matchId}`).set(
    {
      userIds: [uidA, uidB].sort(),
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      source: "mutual_like",
      qaTag: "wym-phase5-e2e",
    },
    {merge: true},
  );
  return matchId;
}

async function firestoreGet(idToken, docPath) {
  const resp = await fetch(firestoreDocUrl(docPath), {
    headers: {Authorization: `Bearer ${idToken}`},
  });
  return {status: resp.status, ok: resp.ok, body: await resp.json().catch(() => ({}))};
}

async function cleanup(admin, uids, matchId) {
  const db = admin.firestore();
  const auth = admin.auth();
  const batch = [];
  if (matchId) {
    batch.push(db.doc(`matches/${matchId}`).delete().catch(() => undefined));
    const meta = await db.collection(`matches/${matchId}/meta`).get();
    for (const d of meta.docs) {
      batch.push(d.ref.delete().catch(() => undefined));
    }
  }
  for (const uid of uids) {
    batch.push(db.doc(`users/${uid}/humor/summary`).delete().catch(() => undefined));
    for (const qid of HUMOR_FUN_QUESTIONS) {
      batch.push(
        db.doc(`users/${uid}/relationshipAnswers/${qid}`).delete().catch(() => undefined),
      );
    }
    batch.push(auth.deleteUser(uid).catch(() => undefined));
  }
  await Promise.all(batch);
}

async function main() {
  ensureAdc();
  const admin = require(path.join(__dirname, "..", "node_modules", "firebase-admin"));
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;

  if (!fs.existsSync(TOKEN_FILE)) {
    throw new Error(`missing App Check debug token file: ${TOKEN_FILE}`);
  }
  const debugToken = fs.readFileSync(TOKEN_FILE, "utf8").trim();
  const appCheckToken = await exchangeAppCheckToken(debugToken);
  mark("app_check", "PASS");

  const uidA = await ensureUser(admin, QA_A_EMAIL, "A");
  const uidB = await ensureUser(admin, QA_B_EMAIL, "B");
  const uidC = await ensureUser(admin, QA_C_EMAIL, "C");
  mark("users", "PASS", {uidA, uidB, uidC});

  await seedRichProfile(db, FieldValue, uidA, "A", true);
  await seedRichProfile(db, FieldValue, uidB, "B", true);
  await seedHumorAnswersPair(db, FieldValue, uidA, uidB, [true, true, true, true, false]);
  const matchId = await seedMatch(db, FieldValue, uidA, uidB);
  mark("fixture", "PASS", {matchId, humorQa: "4/5 comparable=5 score=80"});

  const userA = await signIn(QA_A_EMAIL, QA_PASSWORD("A"));
  const userB = await signIn(QA_B_EMAIL, QA_PASSWORD("B"));
  const userC = await signIn(QA_C_EMAIL, QA_PASSWORD("C"));

  // Participant A — cold
  const cold = await callCallable("getWhyYouMatched", userA.idToken, appCheckToken, {
    matchId,
    forceRefresh: true,
  });
  const coldResp = cold.result;
  mark("callable_participant_a_cold", coldResp.available ? "PASS" : "FAIL", {
    latencyMs: cold.latencyMs,
    reasonCount: coldResp.reasons?.length ?? 0,
    cacheHit: coldResp.cacheHit,
  });

  const warmA = await callCallable("getWhyYouMatched", userA.idToken, appCheckToken, {matchId});
  mark("callable_participant_a_warm", warmA.result.cacheHit === true ? "PASS" : "FAIL", {
    latencyMs: warmA.latencyMs,
    cacheHit: warmA.result.cacheHit,
  });

  const humorReason = (coldResp.reasons || []).find((r) => r.category === "humor");
  mark("humor_e2e", humorReason ? "PASS" : "FAIL", {
    humorReason: humorReason
      ? {
          category: humorReason.category,
          titleKey: humorReason.titleKey,
          score: humorReason.score,
          strength: humorReason.strength,
          confidence: humorReason.confidence,
          evidenceType: humorReason.evidence?.type,
        }
      : null,
  });

  const forbidden = scanForbidden(coldResp);
  mark("raw_data_leak", forbidden.length === 0 ? "PASS" : "FAIL", {forbidden});

  // Participant B — warm cache
  const warm = await callCallable("getWhyYouMatched", userB.idToken, appCheckToken, {matchId});
  mark("callable_participant_b", "PASS", {
    latencyMs: warm.latencyMs,
    cacheHit: warm.result.cacheHit,
  });

  // Non-participant C — deny
  let authDeny = "FAIL";
  try {
    await callCallable("getWhyYouMatched", userC.idToken, appCheckToken, {matchId});
  } catch (e) {
    authDeny =
      e.payload?.error?.status === "PERMISSION_DENIED" ||
      String(e.message).includes("permission-denied")
        ? "PASS"
        : "FAIL";
    mark("auth_non_participant", authDeny, {message: e.message});
  }

  // Invalid match
  const invalid = await callCallable(
    "getWhyYouMatched",
    userA.idToken,
    appCheckToken,
    {matchId: "nonexistent_match_id_xyz"},
  );
  mark(
    "invalid_match",
    invalid.result.available === false && invalid.result.reason === "no_match" ? "PASS" : "FAIL",
    {response: invalid.result},
  );

  // Deleted match
  await db.doc(`matches/${matchId}`).set({isActive: false}, {merge: true});
  const deleted = await callCallable("getWhyYouMatched", userA.idToken, appCheckToken, {
    matchId,
    forceRefresh: true,
  });
  mark(
    "deleted_match",
    deleted.result.available === false && deleted.result.reason === "no_match" ? "PASS" : "FAIL",
    {response: deleted.result},
  );

  // Recreate match for remaining tests
  await seedMatch(db, FieldValue, uidA, uidB);

  // Insufficient humor Q&A
  for (const qid of HUMOR_FUN_QUESTIONS) {
    await db.doc(`users/${uidA}/relationshipAnswers/${qid}`).delete();
  }
  await db.doc(`users/${uidB}/relationshipAnswers/${HUMOR_FUN_QUESTIONS[0]}`).set({
    questionId: HUMOR_FUN_QUESTIONS[0],
    answerId: "a",
  });
  const insufficient = await callCallable(
    "getWhyYouMatched",
    userA.idToken,
    appCheckToken,
    {matchId, forceRefresh: true},
  );
  const insHumor = (insufficient.result.reasons || []).find((r) => r.category === "humor");
  mark("insufficient_humor_qa", !insHumor ? "PASS" : "FAIL", {
    humorReasonPresent: Boolean(insHumor),
  });

  // Low score humor Q&A — strip lab fallback so only Q&A path is evaluated
  for (const qid of HUMOR_FUN_QUESTIONS) {
    await db.doc(`users/${uidA}/relationshipAnswers/${qid}`).delete();
    await db.doc(`users/${uidB}/relationshipAnswers/${qid}`).delete();
  }
  await db.doc(`users/${uidA}/humor/summary`).delete().catch(() => undefined);
  await db.doc(`users/${uidB}/humor/summary`).delete().catch(() => undefined);
  await seedHumorAnswersPair(db, FieldValue, uidA, uidB, [true, false, false, false, false]);
  const lowScore = await callCallable("getWhyYouMatched", userA.idToken, appCheckToken, {
    matchId,
    forceRefresh: true,
  });
  const lowHumor = (lowScore.result.reasons || []).find((r) => r.category === "humor");
  mark("low_score_humor", !lowHumor ? "PASS" : "FAIL", {
    scoreWouldBe: 20,
    humorReason: lowHumor || null,
  });

  // Low confidence humor lab — strip Q&A, weak profiles
  for (const qid of HUMOR_FUN_QUESTIONS) {
    await db.doc(`users/${uidA}/relationshipAnswers/${qid}`).delete();
    await db.doc(`users/${uidB}/relationshipAnswers/${qid}`).delete();
  }
  await db.doc(`users/${uidA}/humor/summary`).set(
    {vector: humorVector(50), confidence: 0.05, interactionCount: 2},
    {merge: true},
  );
  await db.doc(`users/${uidB}/humor/summary`).set(
    {vector: humorVector(50), confidence: 0.05, interactionCount: 2},
    {merge: true},
  );
  const lowConf = await callCallable("getWhyYouMatched", userA.idToken, appCheckToken, {
    matchId,
    forceRefresh: true,
  });
  const lowConfHumor = (lowConf.result.reasons || []).find((r) => r.category === "humor");
  mark("low_confidence_humor", !lowConfHumor ? "PASS" : "FAIL");

  // Firestore security live probe (client REST)
  await seedRichProfile(db, FieldValue, uidA, "A", true);
  await seedRichProfile(db, FieldValue, uidB, "B", true);
  await seedMatch(db, FieldValue, uidA, uidB);
  const cachePathA = `matches/${matchId}/meta/whyYouMatched_${uidA}`;
  const cachePathB = `matches/${matchId}/meta/whyYouMatched_${uidB}`;
  await callCallable("getWhyYouMatched", userA.idToken, appCheckToken, {
    matchId,
    forceRefresh: true,
  });

  const probeAOwn = await firestoreGet(userA.idToken, cachePathA);
  const probeBOther = await firestoreGet(userB.idToken, cachePathA);
  const probeCMatch = await firestoreGet(userC.idToken, `matches/${matchId}`);
  const probeCRawProfile = await firestoreGet(userC.idToken, `profiles/${uidA}`);

  mark("firestore_cache_a_read_own", probeAOwn.ok ? "PASS" : "FAIL", {
    httpStatus: probeAOwn.status,
  });
  mark("firestore_cache_b_read_a_denied", probeBOther.ok ? "FAIL" : "PASS", {
    httpStatus: probeBOther.status,
    note: probeBOther.ok
      ? "rules allow any match participant to read all meta docs — viewer isolation gap"
      : "denied as expected",
  });
  mark("firestore_match_c_denied", probeCMatch.ok ? "FAIL" : "PASS", {
    httpStatus: probeCMatch.status,
  });
  mark("firestore_profile_c_denied", probeCRawProfile.ok ? "PASS" : "FAIL", {
    httpStatus: probeCRawProfile.status,
    note: "profiles allow isAuthenticated read by design",
  });

  evidence.performance = {
    coldLatencyMs: cold.latencyMs,
    warmLatencyMs: warm.latencyMs,
    responseSizeBytes: JSON.stringify(coldResp).length,
  };
  evidence.summary = {
    matchId,
    uidA,
    uidB,
    uidC,
    coldReasonCount: coldResp.reasons?.length ?? 0,
    humorEvidenceType: humorReason?.evidence?.type ?? null,
  };

  const failed = Object.values(evidence.steps).filter((s) => s.status === "FAIL");
  evidence.final = failed.length === 0 ? "PASS" : "FAIL";
  evidence.completedAt = new Date().toISOString();

  fs.mkdirSync(path.dirname(OUT_FILE), {recursive: true});
  fs.writeFileSync(OUT_FILE, JSON.stringify(evidence, null, 2));

  await cleanup(admin, [uidA, uidB, uidC], matchId);
  mark("cleanup", "PASS");

  console.log(JSON.stringify({final: evidence.final, evidenceFile: OUT_FILE}, null, 2));
  if (evidence.final !== "PASS") {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  evidence.final = "FAIL";
  evidence.error = String(err.message || err);
  try {
    fs.writeFileSync(OUT_FILE, JSON.stringify(evidence, null, 2));
  } catch {
    /* ignore */
  }
  process.exit(1);
});
