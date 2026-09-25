/**
 * Reset QA_A / QA_B matching state and emit custom tokens for integration tests.
 * Usage: node tool/seedMatchingRuntimeQa.cjs
 * Writes: integration_test/fixtures/matching_runtime_qa.local.json (gitignored)
 */
const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const PROJECT = "mevora-d6ed0";
const UID_A = process.env.QA_A_UID || "F7CYZWNik3RGv3xQTZRLKWsMnTd2";
const UID_B = process.env.QA_B_UID || "CKLxiWTBtoXik888Wzqicqeuj6t2";
const MATCH_ID = [UID_A, UID_B].sort().join("_");
const LIKE_A_B = `${UID_A}_${UID_B}`;
const LIKE_B_A = `${UID_B}_${UID_A}`;
const BOOTSTRAP = path.join(__dirname, "qaBootstrapAdcFromFirebaseLogin.cjs");
const QA_PASSWORD =
  process.env.QA_E2E_PASSWORD || "MevoraQaE2e!2026";
const FIXTURE_PATH = path.join(
  __dirname,
  "..",
  "integration_test",
  "fixtures",
  "matching_runtime_qa.local.json",
);

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return;
  }
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok || !parsed.adcPath) {
    throw new Error(`ADC bootstrap failed: ${line || boot.stderr}`);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
}

function loadAdmin() {
  ensureAdc();
  const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  return admin;
}

async function deleteCollection(db, ref, batchSize = 200) {
  const snap = await ref.limit(batchSize).get();
  if (snap.empty) {
    return;
  }
  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  if (snap.size >= batchSize) {
    await deleteCollection(db, ref, batchSize);
  }
}

async function clearPairState(db) {
  const refs = [
    db.doc(`matches/${MATCH_ID}`),
    db.doc(`likes/${LIKE_A_B}`),
    db.doc(`likes/${LIKE_B_A}`),
    db.doc(`users/${UID_A}/passedUsers/${UID_B}`),
    db.doc(`users/${UID_B}/passedUsers/${UID_A}`),
  ];
  for (const ref of refs) {
    await ref.delete().catch(() => {});
  }
  await deleteCollection(db, db.collection(`matches/${MATCH_ID}/messages`));
}

async function pauseRelationshipOverlay(db, admin, uid) {
  const cooldownUntil = admin.firestore.Timestamp.fromMillis(
    Date.now() + 60 * 60 * 1000,
  );
  await db.doc(`users/${uid}/relationshipMatch/summary`).set(
    {
      matchingPaused: true,
      matchingEventCount: 1,
      offerCooldownUntil: cooldownUntil,
      offerCooldownReason: "declined",
      offerDismissedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

async function main() {
  const admin = loadAdmin();
  const db = admin.firestore();
  const auth = admin.auth();

  console.log("Seeding matching runtime QA");
  console.log("QA_A=", UID_A);
  console.log("QA_B=", UID_B);
  console.log("matchId=", MATCH_ID);

  await clearPairState(db);
  await Promise.all([
    pauseRelationshipOverlay(db, admin, UID_A),
    pauseRelationshipOverlay(db, admin, UID_B),
  ]);

  const [userA, userB] = await Promise.all([
    auth.getUser(UID_A),
    auth.getUser(UID_B),
  ]);
  const [profileA, profileB] = await Promise.all([
    db.doc(`profiles/${UID_A}`).get(),
    db.doc(`profiles/${UID_B}`).get(),
  ]);
  await Promise.all([
    auth.updateUser(UID_A, {password: QA_PASSWORD}),
    auth.updateUser(UID_B, {password: QA_PASSWORD}),
  ]);

  const fixture = {
    projectId: PROJECT,
    uidA: UID_A,
    uidB: UID_B,
    emailA: userA.email || null,
    emailB: userB.email || null,
    displayNameA:
      profileA.data()?.displayName || userA.displayName || "QA_A",
    displayNameB:
      profileB.data()?.displayName || userB.displayName || "QA_B",
    matchId: MATCH_ID,
    password: QA_PASSWORD,
    seededAt: new Date().toISOString(),
  };

  fs.mkdirSync(path.dirname(FIXTURE_PATH), {recursive: true});
  fs.writeFileSync(FIXTURE_PATH, JSON.stringify(fixture, null, 2));

  console.log("fixture_written", FIXTURE_PATH);
  console.log("pair_state_cleared=true");
  console.log("relationship_overlay_paused=true");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
