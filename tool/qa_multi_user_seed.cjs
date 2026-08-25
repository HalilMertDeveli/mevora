/**
 * Multi-user Auth + Firestore seed for Mevora Firebase Emulator Suite.
 * Safe for local emulators only — does not touch production.
 *
 * Usage (emulators must be running):
 *   node tool/qa_multi_user_seed.cjs
 */
const AUTH = 'http://127.0.0.1:9099';
const FS = 'http://127.0.0.1:8080';
const PROJECT = 'mevora-d6ed0';
const API_KEY = 'fake-api-key';

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

async function signUp(u) {
  const res = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        email: u.email,
        password: u.password,
        displayName: u.displayName,
        returnSecureToken: true,
      }),
    },
  );
  const body = await res.json();
  if (body.error) {
    // Already exists — sign in
    const login = await fetch(
      `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
      {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          email: u.email,
          password: u.password,
          returnSecureToken: true,
        }),
      },
    );
    const loginBody = await login.json();
    if (loginBody.error) throw new Error(JSON.stringify(loginBody.error));
    return loginBody;
  }
  return body;
}

async function setDoc(path, fields) {
  const url = `${FS}/v1/projects/${PROJECT}/databases/(default)/documents/${path}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({fields}),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Firestore ${path}: ${res.status} ${t}`);
  }
  return res.json();
}

function str(v) {
  return {stringValue: String(v)};
}
function bool(v) {
  return {booleanValue: Boolean(v)};
}
function num(v) {
  return {integerValue: String(v)};
}
function dbl(v) {
  return {doubleValue: Number(v)};
}
function ts(d = new Date()) {
  return {timestampValue: d.toISOString()};
}
function arr(values) {
  return {arrayValue: {values}};
}

async function seedProfile(uid, u) {
  const now = new Date();
  await setDoc(`users/${uid}`, {
    uid: str(uid),
    email: str(u.email),
    displayName: str(u.displayName),
    accountStatus: str('active'),
    isActive: bool(true),
    isBanned: bool(false),
    isSmokeTestUser: bool(true),
    profileCompleted: bool(true),
    onboardingCompleted: bool(true),
    lastActiveAt: ts(now),
    updatedAt: ts(now),
    createdAt: ts(now),
  });

  await setDoc(`profiles/${uid}`, {
    uid: str(uid),
    displayName: str(u.displayName),
    name: str(u.displayName),
    bio: str(`QA bio for ${u.displayName} — ğüşöçı`),
    gender: str(u.gender),
    birthDate: str('1998-05-15'),
    age: num(27),
    heightCm: num(170),
    relationshipGoal: str('serious'),
    alcohol: str('sometimes'),
    smoking: str('never'),
    education: str('university'),
    profession: str('Engineer'),
    interests: arr([str('music'), str('travel'), str('coffee')]),
    isDiscoverable: bool(true),
    isActive: bool(true),
    photoCount: num(0),
    updatedAt: ts(now),
    createdAt: ts(now),
  });

  await setDoc(`userPreferences/${uid}`, {
    uid: str(uid),
    lookingFor: str(u.lookingFor),
    preferredGenders: arr([str(u.lookingFor)]),
    minAge: num(21),
    maxAge: num(40),
    maxDistanceKm: num(100),
    updatedAt: ts(now),
  });

  await setDoc(`userLocation/${uid}`, {
    uid: str(uid),
    lat: dbl(41.0082),
    lng: dbl(28.9784),
    geohash: str('sxk97'),
    city: str('Istanbul'),
    country: str('TR'),
    updatedAt: ts(now),
  });

  // Shared relationship answers for matching affinity
  await setDoc(`relationshipAnswers/${uid}`, {
    uid: str(uid),
    answers: {
      mapValue: {
        fields: {
          q1: str('A'),
          q2: str('B'),
          q3: str('A'),
          q4: str('C'),
          q5: str('B'),
        },
      },
    },
    updatedAt: ts(now),
  });
}

async function createMatch(uidA, uidB) {
  const matchId = [uidA, uidB].sort().join('_');
  const now = new Date();
  await setDoc(`matches/${matchId}`, {
    id: str(matchId),
    userIds: arr([str(uidA), str(uidB)]),
    users: arr([str(uidA), str(uidB)]),
    status: str('active'),
    compatibilityScore: num(82),
    createdAt: ts(now),
    updatedAt: ts(now),
    lastMessageAt: ts(now),
  });
  await setDoc(`likes/${uidA}_${uidB}`, {
    fromUserId: str(uidA),
    toUserId: str(uidB),
    action: str('like'),
    createdAt: ts(now),
  });
  await setDoc(`likes/${uidB}_${uidA}`, {
    fromUserId: str(uidB),
    toUserId: str(uidA),
    action: str('like'),
    createdAt: ts(now),
  });
  return matchId;
}

async function addTextMessage(matchId, senderId, receiverId, text) {
  const id = `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const now = new Date();
  await setDoc(`matches/${matchId}/messages/${id}`, {
    id: str(id),
    senderId: str(senderId),
    receiverId: str(receiverId),
    text: str(text),
    type: str('text'),
    createdAt: ts(now),
  });
  return id;
}

async function main() {
  const created = {};
  for (const u of users) {
    const auth = await signUp(u);
    const uid = auth.localId;
    created[u.label] = {uid, email: u.email, password: u.password, displayName: u.displayName};
    await seedProfile(uid, u);
    console.log(`SEED ${u.label} uid=${uid} email=${u.email}`);
  }
  const matchId = await createMatch(created.A.uid, created.B.uid);
  console.log(`MATCH A-B ${matchId}`);
  const msgId = await addTextMessage(
    matchId,
    created.A.uid,
    created.B.uid,
    'Merhaba Test User B — QA multi-emu message',
  );
  console.log(`MESSAGE ${msgId}`);

  const out = {ok: true, users: created, matchId, msgId};
  console.log(JSON.stringify(out, null, 2));
  const fs = await import('node:fs');
  fs.writeFileSync('qa/multi_user_seed.json', JSON.stringify(out, null, 2));
}

main().catch((e) => {
  console.error('SEED FAILED', e);
  process.exit(1);
});
