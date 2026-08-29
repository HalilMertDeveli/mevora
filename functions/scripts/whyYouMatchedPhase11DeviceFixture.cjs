/**
 * Phase 11 — Seed controlled WYM device fixture on mevora-d6ed0 (NOT production).
 * Users: test_wym_device_a / test_wym_device_b
 * Writes: integration_test/fixtures/why_you_matched_device_qa.local.json
 */
const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const PROJECT = "mevora-d6ed0";
const BOOTSTRAP = path.join(__dirname, "..", "..", "tool", "qaBootstrapAdcFromFirebaseLogin.cjs");
const OUT = path.join(
  __dirname,
  "..",
  "..",
  "integration_test",
  "fixtures",
  "why_you_matched_device_qa.local.json",
);

const EMAIL_A = "test_wym_device_a@mevora-qa.test";
const EMAIL_B = "test_wym_device_b@mevora-qa.test";
const PASSWORD = "TestWymDevice_2026!";
const NAME_A = "WYM_DEVICE_A";
const NAME_B = "WYM_DEVICE_B";
const HUMOR_FUN_QUESTIONS = ["rq_002", "rq_005", "rq_008", "rq_011", "rq_014"];

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return;
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok || !parsed.adcPath) {
    throw new Error("ADC bootstrap failed: " + (line || boot.stderr));
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
}

function humorVector(high = 85) {
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

async function ensureUser(admin, email, label, displayName) {
  const auth = admin.auth();
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, {
      password: PASSWORD,
      emailVerified: true,
      displayName,
    });
  } catch {
    user = await auth.createUser({
      email,
      password: PASSWORD,
      emailVerified: true,
      displayName,
    });
  }
  const uid = user.uid;
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.doc(`users/${uid}`).set(
    {
      email,
      displayName,
      isQaUser: true,
      qaTag: "wym-phase11-device",
      profileCompleted: true,
      onboardingCompleted: true,
      accountStatus: "active",
      isActive: true,
      isBanned: false,
      lastActiveAt: now,
      updatedAt: now,
    },
    {merge: true},
  );
  await db.doc(`profiles/${uid}`).set(
    {
      displayName,
      profileCompleted: true,
      onboardingCompleted: true,
      isDiscoverable: true,
      isProfileComplete: true,
      profileModerationStatus: "approved",
      isQaUser: true,
      qaTag: "wym-phase11-device",
      interests: ["music", "travel", "food", "art"],
      languages: ["tr", "en"],
      lifestyle: ["smoking:no", "pets:yes", "drinking:socially"],
      lifestyleProfile: {
        smoking: "no",
        drinking: "socially",
        pets: "yes",
        exercise: "regular",
      },
      birthDate: "1995-01-15",
      age: 30,
      gender: label === "A" ? "male" : "female",
      updatedAt: now,
    },
    {merge: true},
  );
  await db.doc(`userLocation/${uid}`).set(
    {
      lat: label === "A" ? 41.0082 : 41.015,
      lng: label === "A" ? 28.9784 : 28.985,
      latitude: label === "A" ? 41.0082 : 41.015,
      longitude: label === "A" ? 28.9784 : 28.985,
      updatedAt: now,
    },
    {merge: true},
  );
  await db.doc(`users/${uid}/humor/summary`).set(
    {
      vector: humorVector(85),
      confidence: 0.55,
      interactionCount: 12,
      funnyCount: 10,
      notFunnyCount: 2,
      exploredCategories: ["absurd", "meme"],
      version: 1,
      updatedAt: now,
    },
    {merge: true},
  );
  return uid;
}

async function seedHumorAnswers(db, FieldValue, uidA, uidB) {
  for (let i = 0; i < HUMOR_FUN_QUESTIONS.length; i++) {
    const qid = HUMOR_FUN_QUESTIONS[i];
    await db.doc(`users/${uidA}/relationshipAnswers/${qid}`).set(
      {
        questionId: qid,
        answerId: "a",
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    await db.doc(`users/${uidB}/relationshipAnswers/${qid}`).set(
      {
        questionId: qid,
        answerId: i < 4 ? "a" : "b",
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
}

async function seedMatch(db, FieldValue, uidA, uidB) {
  const matchId = [uidA, uidB].sort().join("_");
  await db.doc(`matches/${matchId}`).set(
    {
      userIds: [uidA, uidB].sort(),
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
      matchedAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessage: "WYM device fixture",
      source: "mutual_like",
      qaTag: "wym-phase11-device",
      participantNames: {
        [uidA]: NAME_A,
        [uidB]: NAME_B,
      },
      isNewFor: {
        [uidA]: true,
        [uidB]: true,
      },
    },
    {merge: true},
  );
  return matchId;
}

(async () => {
  ensureAdc();
  const admin = require(path.join(__dirname, "..", "node_modules", "firebase-admin"));
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;

  const uidA = await ensureUser(admin, EMAIL_A, "A", NAME_A);
  const uidB = await ensureUser(admin, EMAIL_B, "B", NAME_B);
  await seedHumorAnswers(db, FieldValue, uidA, uidB);
  const matchId = await seedMatch(db, FieldValue, uidA, uidB);

  const fixture = {
    projectId: PROJECT,
    environment: "development",
    emailA: EMAIL_A,
    emailB: EMAIL_B,
    password: PASSWORD,
    displayNameA: NAME_A,
    displayNameB: NAME_B,
    uidA,
    uidB,
    matchId,
    seededAt: new Date().toISOString(),
  };
  fs.mkdirSync(path.dirname(OUT), {recursive: true});
  fs.writeFileSync(OUT, JSON.stringify(fixture, null, 2));
  console.log(JSON.stringify({ok: true, fixture: OUT, matchId, uidA, uidB}));
})().catch((e) => {
  console.error(String(e && e.stack ? e.stack : e));
  process.exit(1);
});
