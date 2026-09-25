/**
 * Seeds the two Core Dating Flow acceptance identities into the Firebase
 * Emulator Suite. Refuses to run unless BOTH emulator hosts are set, so it can
 * never reach a cloud project.
 *
 * What it seeds is only the *prerequisites* the real discovery engine checks:
 * account, profile, preferences, location and three photos approved through the
 * server-owned moderation ledger (writing moderationStatus onto profiles.photos
 * alone is reverted by enforceProfilePhotoModeration by design).
 *
 * It deliberately does NOT create likes, matches, conversations or messages.
 * Those must come from the real app + backend during the acceptance run.
 *
 * `isSmokeTestUser: true` on both accounts uses the product's own
 * passesSmokeDiscoveryIsolation gate so the pair discovers only each other.
 * Every other eligibility filter still has to pass genuinely.
 */
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error("refusing to run: set FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST");
  process.exit(2);
}

/** firebase-admin lives in functions/node_modules, not at the repo root. */
function requireAdmin() {
  const {createRequire} = require("node:module");
  const path = require("node:path");
  const fromFunctions = createRequire(
    path.join(__dirname, "..", "functions", "package.json"),
  );
  try {
    return fromFunctions("firebase-admin");
  } catch (_) {
    try {
      return require("firebase-admin");
    } catch (_err) {
      console.error(
        "firebase-admin not found — run: npm --prefix functions ci",
      );
      process.exit(2);
    }
  }
}
const admin = requireAdmin();

const PROJECT = process.env.QA_PROJECT || "mevora-d6ed0";
const STAMP = process.env.QA_STAMP || String(Date.now());
const PASSWORD = process.env.QA_PASSWORD;
if (!PASSWORD) {
  console.error("refusing to run: set QA_PASSWORD");
  process.exit(2);
}

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const auth = admin.auth();

const people = [
  {
    key: "A",
    email: `qa_core_a_${STAMP}@mevora.test`,
    displayName: `QA_CORE_A_${STAMP}`,
    gender: "male",
    interestedIn: "female",
    birthDate: new Date("1996-04-11T00:00:00Z"),
  },
  {
    key: "B",
    email: `qa_core_b_${STAMP}@mevora.test`,
    displayName: `QA_CORE_B_${STAMP}`,
    gender: "female",
    interestedIn: "male",
    birthDate: new Date("1997-08-23T00:00:00Z"),
  },
];

// Same city so the pair lands in the nearby tier rather than no_location.
const CITY = "Istanbul";
const LAT = 41.0082;
const LNG = 28.9784;

async function upsertAuthUser(person) {
  const existing = await auth.getUserByEmail(person.email).catch(() => null);
  if (existing) {
    return existing.uid;
  }
  const created = await auth.createUser({
    email: person.email,
    password: PASSWORD,
    displayName: person.displayName,
    emailVerified: true,
  });
  return created.uid;
}

function photoRecords(uid) {
  return [0, 1, 2].map((i) => {
    const imageId = `qa_photo_${i + 1}`;
    return {
      imageId,
      storagePath: `users/${uid}/profile/photos/${imageId}.jpg`,
      downloadUrl: `https://qa.invalid/${uid}/${imageId}.jpg`,
      record: {
        id: imageId,
        downloadUrl: `https://qa.invalid/${uid}/${imageId}.jpg`,
        thumbUrl: null,
        order: i,
        isPrimary: i === 0,
        moderationStatus: "approved",
        storagePath: `users/${uid}/profile/photos/${imageId}.jpg`,
      },
    };
  });
}

async function seedPerson(person) {
  const uid = await upsertAuthUser(person);
  const photos = photoRecords(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Ledger first: the reconciling trigger reads this as the authority, so the
  // approved photos survive instead of being reverted to pending.
  for (const p of photos) {
    await db.doc(`users/${uid}/photoModeration/${p.imageId}`).set(
      {
        imageId: p.imageId,
        status: "approved",
        reason: null,
        moderatedBy: "qa-acceptance-seed",
        moderatedAt: now,
        storagePath: p.storagePath,
        downloadUrl: p.downloadUrl,
        thumbUrl: null,
        updatedAt: now,
      },
      {merge: true},
    );
  }

  await db.doc(`users/${uid}`).set(
    {
      uid,
      email: person.email,
      isSmokeTestUser: true,
      accountStatus: "active",
      isBanned: false,
      isSuspended: false,
      onboardingComplete: true,
      lastActiveAt: now,
      createdAt: now,
      updatedAt: now,
    },
    {merge: true},
  );

  await db.doc(`profiles/${uid}`).set(
    {
      uid,
      displayName: person.displayName,
      name: person.displayName,
      bio: "Core dating flow acceptance fixture.",
      gender: person.gender,
      birthDate: admin.firestore.Timestamp.fromDate(person.birthDate),
      city: CITY,
      photos: photos.map((p) => p.record),
      isDiscoverable: true,
      profileCompleted: true,
      profileModerationStatus: "approved",
      updatedAt: now,
      createdAt: now,
    },
    {merge: true},
  );

  await db.doc(`userPreferences/${uid}`).set(
    {
      uid,
      interestedIn: person.interestedIn,
      minAge: 18,
      maxAge: 60,
      maxDistanceKm: 200,
      updatedAt: now,
    },
    {merge: true},
  );

  await db.doc(`userLocation/${uid}`).set(
    {uid, latitude: LAT, longitude: LNG, city: CITY, updatedAt: now},
    {merge: true},
  );

  return {key: person.key, uid, email: person.email, displayName: person.displayName};
}

(async () => {
  const out = [];
  for (const person of people) {
    out.push(await seedPerson(person));
  }

  // Prove no stale relationship exists between the pair before the run starts.
  const [a, b] = out;
  const matchId = [a.uid, b.uid].sort().join("_");
  const checks = {
    canonicalMatchId: matchId,
    matchDocExists: (await db.doc(`matches/${matchId}`).get()).exists,
    matchesContainingA: (
      await db.collection("matches").where("userIds", "array-contains", a.uid).get()
    ).size,
    likesFromA: (await db.collection("likes").where("fromUserId", "==", a.uid).get()).size,
    likesFromB: (await db.collection("likes").where("fromUserId", "==", b.uid).get()).size,
  };

  console.log(JSON.stringify({project: PROJECT, stamp: STAMP, users: out, preRunState: checks}, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error("seed failed:", err && err.message ? err.message : err);
  process.exit(1);
});
