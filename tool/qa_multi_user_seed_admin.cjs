/**
 * Admin SDK seed against local Firebase Emulator Suite (bypasses security rules).
 * Never points at production — requires emulator env vars.
 */
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:9199';

const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const fs = require('node:fs');

initializeApp({projectId: 'mevora-d6ed0'});
const auth = getAuth();
const db = getFirestore();

const users = [
  {
    label: 'A',
    email: 'qa-a@mevora.test',
    password: 'QaTest!A9Mevora',
    displayName: 'Test User A',
    gender: 'male',
    lookingFor: 'female',
  },
  {
    label: 'B',
    email: 'qa-b@mevora.test',
    password: 'QaTest!B9Mevora',
    displayName: 'Test User B',
    gender: 'female',
    lookingFor: 'male',
  },
  {
    label: 'C',
    email: 'qa-c@mevora.test',
    password: 'QaTest!C9Mevora',
    displayName: 'Test User C',
    gender: 'female',
    lookingFor: 'male',
  },
];

async function ensureUser(u) {
  let user;
  try {
    user = await auth.getUserByEmail(u.email);
    await auth.updateUser(user.uid, {
      password: u.password,
      displayName: u.displayName,
      emailVerified: true,
    });
  } catch {
    user = await auth.createUser({
      email: u.email,
      password: u.password,
      displayName: u.displayName,
      emailVerified: true,
    });
  }
  return user;
}

async function seedProfile(uid, u) {
  const base = {
    uid,
    email: u.email,
    displayName: u.displayName,
    accountStatus: 'active',
    isActive: true,
    isBanned: false,
    isSmokeTestUser: true,
    profileCompleted: true,
    onboardingCompleted: true,
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  };
  await db.doc(`users/${uid}`).set(base, {merge: true});
  await db.doc(`profiles/${uid}`).set(
    {
      uid,
      displayName: u.displayName,
      name: u.displayName,
      bio: `QA bio for ${u.displayName} — ğüşöçı`,
      gender: u.gender,
      birthDate: '1998-05-15',
      age: 27,
      heightCm: 170,
      relationshipGoal: 'serious',
      alcohol: 'sometimes',
      smoking: 'never',
      education: 'university',
      profession: 'Engineer',
      interests: ['music', 'travel', 'coffee'],
      isDiscoverable: true,
      isActive: true,
      photoCount: 0,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`userPreferences/${uid}`).set(
    {
      uid,
      lookingFor: u.lookingFor,
      preferredGenders: [u.lookingFor],
      minAge: 21,
      maxAge: 40,
      maxDistanceKm: 100,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`userLocation/${uid}`).set(
    {
      uid,
      lat: 41.0082,
      lng: 28.9784,
      geohash: 'sxk97',
      city: 'Istanbul',
      country: 'TR',
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`relationshipAnswers/${uid}`).set(
    {
      uid,
      answers: {q1: 'A', q2: 'B', q3: 'A', q4: 'C', q5: 'B'},
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

async function createMatch(uidA, uidB) {
  const matchId = [uidA, uidB].sort().join('_');
  await db.doc(`matches/${matchId}`).set(
    {
      id: matchId,
      userIds: [uidA, uidB],
      users: [uidA, uidB],
      status: 'active',
      compatibilityScore: 82,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessagePreview: 'Merhaba Test User B — QA multi-emu message',
      lastMessageSenderId: uidA,
    },
    {merge: true},
  );
  await db.doc(`likes/${uidA}_${uidB}`).set({
    fromUserId: uidA,
    toUserId: uidB,
    action: 'like',
    createdAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`likes/${uidB}_${uidA}`).set({
    fromUserId: uidB,
    toUserId: uidA,
    action: 'like',
    createdAt: FieldValue.serverTimestamp(),
  });
  const msgRef = db.collection(`matches/${matchId}/messages`).doc();
  await msgRef.set({
    id: msgRef.id,
    senderId: uidA,
    receiverId: uidB,
    text: 'Merhaba Test User B — QA multi-emu message',
    type: 'text',
    createdAt: FieldValue.serverTimestamp(),
  });
  return {matchId, messageId: msgRef.id};
}

async function main() {
  const created = {};
  for (const u of users) {
    const user = await ensureUser(u);
    await seedProfile(user.uid, u);
    created[u.label] = {
      uid: user.uid,
      email: u.email,
      password: u.password,
      displayName: u.displayName,
    };
    console.log(`SEED ${u.label} uid=${user.uid}`);
  }
  const {matchId, messageId} = await createMatch(created.A.uid, created.B.uid);
  console.log(`MATCH ${matchId} MSG ${messageId}`);

  // Change B answer for cache regression later
  await db.doc(`relationshipAnswers/${created.B.uid}`).set(
    {
      answers: {q1: 'A', q2: 'B', q3: 'CHANGED', q4: 'C', q5: 'B'},
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  const out = {ok: true, users: created, matchId, messageId, emulator: true};
  fs.mkdirSync('qa', {recursive: true});
  fs.writeFileSync('qa/multi_user_seed.json', JSON.stringify(out, null, 2));
  console.log(JSON.stringify(out, null, 2));
}

main().catch((e) => {
  console.error('SEED FAILED', e);
  process.exit(1);
});
