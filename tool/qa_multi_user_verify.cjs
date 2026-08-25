process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const fs = require('node:fs');

initializeApp({projectId: 'mevora-d6ed0'});
const db = getFirestore();
const auth = getAuth();

async function main() {
  const seed = JSON.parse(fs.readFileSync('qa/multi_user_seed.json', 'utf8'));
  const report = {ok: true, checks: []};
  function check(name, pass, detail) {
    report.checks.push({name, pass, detail});
    if (!pass) report.ok = false;
    console.log(`${pass ? 'PASS' : 'FAIL'} ${name} ${detail || ''}`);
  }

  for (const label of ['A', 'B', 'C']) {
    const u = seed.users[label];
    const user = await auth.getUser(u.uid);
    check(`auth-${label}`, user.email === u.email, user.email);
    const profile = await db.doc(`profiles/${u.uid}`).get();
    check(`profile-${label}`, profile.exists && profile.data().displayName === u.displayName, JSON.stringify(profile.data()?.displayName));
    const answers = await db.doc(`relationshipAnswers/${u.uid}`).get();
    check(`answers-${label}`, answers.exists, JSON.stringify(answers.data()?.answers));
  }

  const match = await db.doc(`matches/${seed.matchId}`).get();
  check('match-exists', match.exists && match.data()?.status === 'active', seed.matchId);
  const msgs = await db.collection(`matches/${seed.matchId}/messages`).get();
  check('messages-count', msgs.size >= 1, String(msgs.size));
  const first = msgs.docs[0]?.data();
  check(
    'message-text-not-mevora-hardcoded-peer',
    first?.text?.includes('Test User B') === true,
    first?.text,
  );
  check('message-sender-is-A', first?.senderId === seed.users.A.uid, first?.senderId);

  // Answer change persistence for B
  const bAnswers = (await db.doc(`relationshipAnswers/${seed.users.B.uid}`).get()).data()?.answers;
  check('b-answer-changed-q3', bAnswers?.q3 === 'CHANGED', JSON.stringify(bAnswers));

  fs.writeFileSync('qa/multi_user_verify.json', JSON.stringify(report, null, 2));
  process.exit(report.ok ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
