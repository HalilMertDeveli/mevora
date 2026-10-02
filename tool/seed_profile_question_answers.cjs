/**
 * Emulator-only dev backfill: gives every profile visible questionAnswers for
 * the profile Q&A UI ("Onu biraz daha tanı"). Same job as
 * seed_profile_question_answers.mjs — keep the two in sync.
 *
 * - If users/{uid}/relationshipAnswers exist → copy into questionAnswers
 * - Else → write a small demo set from the relationship catalog ids
 *
 * It writes to every profile it finds and invents answers for members who gave
 * none, so it must never reach a real project: it refuses to run unless
 * FIRESTORE_EMULATOR_HOST is a loopback address, and it loads no cloud
 * credential.
 *
 * Usage (PowerShell, from the repo root, emulators already up):
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   node tool/seed_profile_question_answers.cjs
 */
// Checked before firebase-admin is loaded, so a refusal makes no network call.
const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!firestoreHost || !LOOPBACK_HOST.test(firestoreHost)) {
  console.error(
    'REFUSING TO RUN: FIRESTORE_EMULATOR_HOST must be set to a loopback emulator ' +
      'address (e.g. 127.0.0.1:8080). This script only ever seeds the Emulator Suite.',
  );
  process.exit(2);
}

const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'mevora-d6ed0';
const DEMO_ANSWERS = [
  {questionId: 'rq_001', answerId: 'a'},
  {questionId: 'rq_003', answerId: 'b'},
  {questionId: 'rq_004', answerId: 'b'},
  {questionId: 'rq_007', answerId: 'a'},
  {questionId: 'rq_010', answerId: 'c'},
  {questionId: 'rq_015', answerId: 'b'},
];

initializeApp({projectId: PROJECT_ID});
const db = getFirestore();

async function seedUser(uid) {
  const matching = await db.collection(`users/${uid}/relationshipAnswers`).get();
  const rows = matching.docs
    .map((doc) => {
      const data = doc.data() || {};
      return {
        questionId: String(data.questionId || doc.id),
        answerId: String(data.answerId || ''),
      };
    })
    .filter((row) => /^rq_\d{3}$/.test(row.questionId) && /^[abc]$/.test(row.answerId));

  const sourceRows = rows.length > 0 ? rows.slice(0, 12) : DEMO_ANSWERS;
  const source = rows.length > 0 ? 'relationshipAnswers' : 'demo';
  const existing = await db.collection(`users/${uid}/questionAnswers`).get();
  const have = new Set(existing.docs.map((d) => d.id));
  const batch = db.batch();
  let written = 0;
  for (const row of sourceRows) {
    if (have.has(row.questionId)) continue;
    batch.set(
      db.doc(`users/${uid}/questionAnswers/${row.questionId}`),
      {
        questionId: row.questionId,
        answerId: row.answerId,
        isVisible: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        seeded: true,
      },
      {merge: true},
    );
    written += 1;
  }
  if (written > 0) await batch.commit();
  return {uid, source, written, available: sourceRows.length};
}

(async () => {
  const profiles = await db.collection('profiles').get();
  const uids = profiles.docs.map((d) => d.id);
  console.log(`Emulator ${firestoreHost}, project ${PROJECT_ID}: ${uids.length} profiles`);
  let total = 0;
  for (const uid of uids) {
    const result = await seedUser(uid);
    total += result.written;
    console.log(`${result.uid} ← ${result.source}: wrote ${result.written}/${result.available}`);
  }
  console.log(`Done. Total new docs: ${total}`);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
