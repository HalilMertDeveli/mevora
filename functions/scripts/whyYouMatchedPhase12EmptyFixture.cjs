/**
 * Phase 12 — Seed a controlled EMPTY WYM match on mevora-d6ed0.
 * Pair: device A (existing) + empty partner with no shared humor/interests/lifestyle.
 * Writes: integration_test/fixtures/why_you_matched_device_empty_qa.local.json
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
  "why_you_matched_device_empty_qa.local.json",
);

const EMAIL_A = "test_wym_device_a@mevora-qa.test";
const EMAIL_E = "test_wym_device_empty@mevora-qa.test";
const PASSWORD = "TestWymDevice_2026!";
const NAME_A = "WYM_DEVICE_A";
const NAME_E = "WYM_EMPTY_B";

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

async function ensureUser(admin, email, displayName, sparse) {
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
      qaTag: "wym-phase12-empty",
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

  if (sparse) {
    // Intentionally sparse: no interests/lifestyle/humor — maximize empty WYM.
    await db.doc(`profiles/${uid}`).set(
      {
        displayName,
        profileCompleted: true,
        onboardingCompleted: true,
        isDiscoverable: true,
        isProfileComplete: true,
        profileModerationStatus: "approved",
        isQaUser: true,
        qaTag: "wym-phase12-empty",
        interests: [],
        languages: [],
        lifestyle: [],
        lifestyleProfile: {},
        birthDate: "1998-06-01",
        age: 27,
        gender: "female",
        updatedAt: now,
      },
      {merge: true},
    );
    const humor = await db.doc(`users/${uid}/humor/summary`).get();
    if (humor.exists) {
      await db.doc(`users/${uid}/humor/summary`).delete();
    }
    const answers = await db.collection(`users/${uid}/relationshipAnswers`).get();
    const batch = db.batch();
    answers.docs.forEach((d) => batch.delete(d.ref));
    if (!answers.empty) await batch.commit();
  }

  return uid;
}

async function seedMatch(db, FieldValue, uidA, uidE) {
  const matchId = [uidA, uidE].sort().join("_");
  await db.doc(`matches/${matchId}`).set(
    {
      userIds: [uidA, uidE].sort(),
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
      matchedAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessage: "WYM empty fixture",
      source: "mutual_like",
      qaTag: "wym-phase12-empty",
      participantNames: {
        [uidA]: NAME_A,
        [uidE]: NAME_E,
      },
      isNewFor: {
        [uidA]: true,
        [uidE]: true,
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

  const uidA = await ensureUser(admin, EMAIL_A, NAME_A, false);
  const uidE = await ensureUser(admin, EMAIL_E, NAME_E, true);
  const matchId = await seedMatch(db, FieldValue, uidA, uidE);

  const fixture = {
    projectId: PROJECT,
    environment: "development",
    emailA: EMAIL_A,
    emailEmpty: EMAIL_E,
    password: PASSWORD,
    displayNameA: NAME_A,
    displayNameEmpty: NAME_E,
    uidA,
    uidEmpty: uidE,
    matchId,
    seededAt: new Date().toISOString(),
  };
  fs.mkdirSync(path.dirname(OUT), {recursive: true});
  fs.writeFileSync(OUT, JSON.stringify(fixture, null, 2));
  console.log(JSON.stringify({ok: true, fixture: OUT, matchId, uidA, uidEmpty: uidE}));
})().catch((e) => {
  console.error(String(e && e.stack ? e.stack : e));
  process.exit(1);
});
