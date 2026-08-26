/**
 * Dev backfill: ensure every profile has visible questionAnswers for
 * "Onu biraz daha tanı" / profile Q&A UI.
 *
 * - If users/{uid}/relationshipAnswers exist → copy into questionAnswers
 * - Else → write a small demo set from the relationship catalog ids
 *
 * Usage (from repo root, with ADC / gcloud auth):
 *   node tool/seed_profile_question_answers.mjs
 */
import {initializeApp, applicationDefault} from 'firebase-admin/app';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'mevora-d6ed0';

/** Demo picks when a user never answered matching questions. */
const DEMO_ANSWERS = [
  {questionId: 'rq_001', answerId: 'a'},
  {questionId: 'rq_003', answerId: 'b'},
  {questionId: 'rq_004', answerId: 'b'},
  {questionId: 'rq_007', answerId: 'a'},
  {questionId: 'rq_010', answerId: 'c'},
  {questionId: 'rq_015', answerId: 'b'},
];

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

const db = getFirestore();

async function listProfileUids() {
  const snap = await db.collection('profiles').get();
  return snap.docs.map((d) => d.id);
}

async function loadRelationshipAnswers(uid) {
  const snap = await db.collection(`users/${uid}/relationshipAnswers`).get();
  return snap.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      questionId: String(data.questionId || doc.id),
      answerId: String(data.answerId || ''),
    };
  }).filter((row) => /^rq_\d{3}$/.test(row.questionId) && /^[abc]$/.test(row.answerId));
}

async function existingQuestionAnswerIds(uid) {
  const snap = await db.collection(`users/${uid}/questionAnswers`).get();
  return new Set(snap.docs.map((d) => d.id));
}

async function upsertVisibleAnswers(uid, rows, {max = 12} = {}) {
  const existing = await existingQuestionAnswerIds(uid);
  const batch = db.batch();
  let written = 0;
  for (const row of rows) {
    if (written >= max) {
      break;
    }
    if (existing.has(row.questionId)) {
      continue;
    }
    const ref = db.doc(`users/${uid}/questionAnswers/${row.questionId}`);
    batch.set(
      ref,
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
  if (written > 0) {
    await batch.commit();
  }
  return written;
}

async function seedUser(uid) {
  const fromMatching = await loadRelationshipAnswers(uid);
  if (fromMatching.length > 0) {
    const n = await upsertVisibleAnswers(uid, fromMatching, {max: 12});
    return {uid, source: 'relationshipAnswers', written: n, available: fromMatching.length};
  }
  const n = await upsertVisibleAnswers(uid, DEMO_ANSWERS, {max: DEMO_ANSWERS.length});
  return {uid, source: 'demo', written: n, available: DEMO_ANSWERS.length};
}

async function main() {
  const uids = await listProfileUids();
  console.log(`Project ${PROJECT_ID}: ${uids.length} profiles`);
  const results = [];
  for (const uid of uids) {
    results.push(await seedUser(uid));
  }
  for (const row of results) {
    console.log(
      `${row.uid} ← ${row.source}: wrote ${row.written}/${row.available}`,
    );
  }
  const total = results.reduce((sum, row) => sum + row.written, 0);
  console.log(`Done. Total new questionAnswers docs: ${total}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
