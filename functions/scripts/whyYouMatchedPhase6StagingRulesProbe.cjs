/**
 * WYM Phase 6 — Firestore rules live probe (cache viewer isolation).
 *
 * Usage:
 *   node functions/scripts/whyYouMatchedPhase6StagingRulesProbe.cjs
 *   WYM_E2E_PROJECT=mevora-staging node functions/scripts/whyYouMatchedPhase6StagingRulesProbe.cjs
 */
const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');

const PROJECT = process.env.WYM_E2E_PROJECT || 'mevora-staging';
const BOOTSTRAP = path.join(__dirname, '..', '..', 'tool', 'qaBootstrapAdcFromFirebaseLogin.cjs');
const OUT_FILE = path.join(__dirname, '..', '..', 'tool', 'whyYouMatchedPhase6RulesEvidence.json');

const PROJECT_CONFIG = {
  'mevora-d6ed0': {
    apiKey: 'AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw',
  },
  'mevora-staging': {
    apiKey: 'AIzaSyC7dWuaKZmX1c5q4QyQPLUKBPhRvNSqaW0',
  },
};

const QA_A_EMAIL = 'test_wym_a@mevora-qa.test';
const QA_B_EMAIL = 'test_wym_b@mevora-qa.test';
const QA_C_EMAIL = 'test_wym_c@mevora-qa.test';
const QA_PASSWORD = (label) => `TestWym_${label}_2026!`;

const evidence = {
  phase: 'wym-phase6-rules-probe',
  project: PROJECT,
  startedAt: new Date().toISOString(),
  probes: {},
  final: 'BLOCKED',
};

function mark(name, status, detail = {}) {
  evidence.probes[name] = {status, ...detail, at: new Date().toISOString()};
  console.log(JSON.stringify({probe: name, status, ...detail}));
}

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return process.env.GOOGLE_APPLICATION_CREDENTIALS;
  }
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: 'utf8'});
  const line = (boot.stdout || '').trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || '{}');
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

function firestoreDocUrl(docPath) {
  return `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}`;
}

async function signIn(email, password) {
  const {apiKey} = projectConfig();
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || !body.idToken) {
    throw new Error(`signIn-failed ${email} status=${resp.status} ${body.error?.message || ''}`);
  }
  return {idToken: body.idToken, uid: body.localId, email};
}

async function firestoreGet(idToken, docPath) {
  const resp = await fetch(firestoreDocUrl(docPath), {
    headers: {Authorization: `Bearer ${idToken}`},
  });
  return {status: resp.status, ok: resp.ok, body: await resp.json().catch(() => ({}))};
}

async function ensureUser(admin, email, label) {
  const auth = admin.auth();
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
  return user.uid;
}

async function main() {
  ensureAdc();
  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;

  const uidA = await ensureUser(admin, QA_A_EMAIL, 'A');
  const uidB = await ensureUser(admin, QA_B_EMAIL, 'B');
  await ensureUser(admin, QA_C_EMAIL, 'C');

  const userA = await signIn(QA_A_EMAIL, QA_PASSWORD('A'));
  const userB = await signIn(QA_B_EMAIL, QA_PASSWORD('B'));
  const userC = await signIn(QA_C_EMAIL, QA_PASSWORD('C'));
  const matchId = [uidA, uidB].sort().join('_');

  await db.doc(`matches/${matchId}`).set({
    userIds: [uidA, uidB].sort(),
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    lastMessageAt: FieldValue.serverTimestamp(),
    source: 'mutual_like',
    qaTag: 'wym-phase6-rules-probe',
  }, {merge: true});

  const cachePathA = `matches/${matchId}/meta/whyYouMatched_${uidA}`;
  const cachePathB = `matches/${matchId}/meta/whyYouMatched_${uidB}`;

  await db.doc(cachePathA).set({
    viewerUid: uidA,
    reasons: [{category: 'humor', score: 72}],
    cachedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.doc(cachePathB).set({
    viewerUid: uidB,
    reasons: [{category: 'interests', score: 68}],
    cachedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  const probeAOwn = await firestoreGet(userA.idToken, cachePathA);
  const probeBOwn = await firestoreGet(userB.idToken, cachePathB);
  const probeAOther = await firestoreGet(userA.idToken, cachePathB);
  const probeBOther = await firestoreGet(userB.idToken, cachePathA);
  const probeCOtherA = await firestoreGet(userC.idToken, cachePathA);
  const probeCOtherB = await firestoreGet(userC.idToken, cachePathB);

  mark('A_read_A_cache', probeAOwn.ok ? 'PASS' : 'FAIL', {httpStatus: probeAOwn.status});
  mark('B_read_B_cache', probeBOwn.ok ? 'PASS' : 'FAIL', {httpStatus: probeBOwn.status});
  mark('A_read_B_cache', probeAOther.ok ? 'FAIL' : 'PASS', {httpStatus: probeAOther.status});
  mark('B_read_A_cache', probeBOther.ok ? 'FAIL' : 'PASS', {httpStatus: probeBOther.status});
  mark('C_read_A_cache', probeCOtherA.ok ? 'FAIL' : 'PASS', {httpStatus: probeCOtherA.status});
  mark('C_read_B_cache', probeCOtherB.ok ? 'FAIL' : 'PASS', {httpStatus: probeCOtherB.status});

  await db.doc(cachePathA).delete().catch(() => undefined);
  await db.doc(cachePathB).delete().catch(() => undefined);

  const failed = Object.values(evidence.probes).filter((p) => p.status === 'FAIL');
  evidence.final = failed.length === 0 ? 'PASS' : 'FAIL';
  evidence.completedAt = new Date().toISOString();
  evidence.summary = {matchId, uidA, uidB};

  fs.mkdirSync(path.dirname(OUT_FILE), {recursive: true});
  fs.writeFileSync(OUT_FILE, JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify({final: evidence.final, evidenceFile: OUT_FILE}, null, 2));
  if (evidence.final !== 'PASS') {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
