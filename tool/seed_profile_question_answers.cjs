const {initializeApp, applicationDefault} = require('firebase-admin/app');
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

initializeApp({credential: applicationDefault(), projectId: PROJECT_ID});
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
  console.log(`Project ${PROJECT_ID}: ${uids.length} profiles`);
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
