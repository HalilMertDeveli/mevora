#!/usr/bin/env node
/**
 * Seeds a Mevora Picks candidate pool into the Firebase Emulator Suite, so the
 * finite daily batch can be tested by hand with the QA users from
 * tool/seedEmulatorQaUsers.cjs (run that first).
 *
 * What it creates (all uids start with "qa_pick_", nothing else is touched
 * except the QA users' Picks-relevant profile fields and batches):
 *   - 24 strong men and 24 strong women near Istanbul: same relationship goal,
 *     interests and lifestyle as the QA users, so they clear the Picks quality
 *     floor — enough to fill a 10- or 15-Pick day and then some;
 *   - 8 weak candidates of each gender (nothing in common): never Picks, the
 *     low-quality filler that must not appear;
 *   - 3 strong candidates of each gender in Berlin: outside the 100 km gate.
 *   Photos go through the moderation ledger exactly like the QA users', so the
 *   Functions emulator must be running.
 *
 * Usage (PowerShell, from the repo root, emulators already running):
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   node tool/seedEmulatorPicksPool.cjs            # (re)create the pool
 *   node tool/seedEmulatorPicksPool.cjs --small    # only 3 strong per gender: lowSupply
 *   node tool/seedEmulatorPicksPool.cjs --new-day  # expire the QA users' batches now,
 *                                                  # as if Istanbul midnight had passed
 *
 * Every run also deletes the QA users' current batches, so the next Picks
 * open generates a fresh day from the pool as it now is.
 */
const path = require("node:path");
const {createRequire} = require("node:module");

const PROJECT = process.env.QA_PROJECT_ID || "mevora-d6ed0";
const args = process.argv.slice(2);
const SMALL = args.includes("--small");
const NEW_DAY_ONLY = args.includes("--new-day");

// Hard safety gate, as in seedEmulatorQaUsers.cjs: without both emulator hosts
// the Admin SDK would talk to production.
for (const name of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]) {
  const value = process.env[name];
  if (!value || !/^(127\.0\.0\.1|localhost|0\.0\.0\.0|10\.0\.2\.2):\d+$/.test(value)) {
    console.error(`REFUSING TO RUN: ${name} must point at a local emulator (got "${value ?? ""}").`);
    process.exit(1);
  }
}

const fromFunctions = createRequire(path.join(__dirname, "..", "functions", "package.json"));
let admin;
try {
  admin = fromFunctions("firebase-admin");
} catch (_) {
  console.error("firebase-admin not found — run: npm --prefix functions ci");
  process.exit(1);
}
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

const QA_USERS = ["qa_user_a", "qa_user_b", "qa_user_c", "qa_user_d"];
/** What the QA users and the strong pool share: enough for the quality floor. */
const SHARED = {
  relationshipGoal: "longTerm",
  interests: ["hiking", "jazz", "cooking", "chess"],
  lifestyle: ["nonsmoker", "earlybird"],
};
const WEAK = {relationshipGoal: "casual", interests: ["karaoke"], lifestyle: ["smoker", "nightowl"]};
const ISTANBUL = {lat: 41.0082, lng: 28.9784};
const BERLIN = {lat: 52.52, lng: 13.405};

const birthDateFor = (age) => new Date(new Date().getFullYear() - age, 5, 15);

async function deleteQuery(query) {
  const snap = await query.get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  return snap.size;
}

async function clearPool() {
  const profiles = await db.collection("profiles").where("qaPicksPool", "==", true).get();
  for (const doc of profiles.docs) {
    const uid = doc.id;
    await deleteQuery(db.collection(`users/${uid}/photoModeration`));
    await Promise.all([
      db.doc(`profiles/${uid}`).delete(),
      db.doc(`users/${uid}`).delete(),
      db.doc(`userPreferences/${uid}`).delete(),
      db.doc(`userLocation/${uid}`).delete(),
    ]);
  }
  return profiles.size;
}

async function clearBatches() {
  await Promise.all(QA_USERS.map((uid) => db.doc(`users/${uid}/mevoraPicks/current`).delete()));
}

async function seedCandidate({uid, gender, seeks, place, traits, age}) {
  const birthDate = birthDateFor(age);
  for (const index of [0, 1, 2]) {
    const imageId = `${uid}_photo_${index}`;
    await db.doc(`users/${uid}/photoModeration/${imageId}`).set({
      imageId,
      status: "approved",
      reason: null,
      moderatedBy: "emulator-picks-pool",
      moderatedAt: FieldValue.serverTimestamp(),
      storagePath: `users/${uid}/profile/photos/${imageId}.jpg`,
      downloadUrl: `https://picsum.photos/seed/${imageId}/600/800`,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await db.doc(`users/${uid}`).set({
    uid,
    isBanned: false,
    isSuspended: false,
    accountStatus: "active",
    birthDate: Timestamp.fromDate(birthDate),
    lastActiveAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`profiles/${uid}`).set({
    uid,
    qaPicksPool: true,
    displayName: uid.replace("qa_pick_", "Pick ").replace(/_/g, " "),
    gender,
    age,
    bio: "Emulator Picks pool fixture.",
    isDiscoverable: true,
    profileCompleted: true,
    onboardingCompleted: true,
    profileModerationStatus: "approved",
    moderationStatus: "approved",
    ...traits,
    photos: [0, 1, 2].map((index) => ({
      id: `${uid}_photo_${index}`,
      storagePath: `users/${uid}/profile/photos/${uid}_photo_${index}.jpg`,
      downloadUrl: `https://picsum.photos/seed/${uid}_photo_${index}/600/800`,
      thumbUrl: `https://picsum.photos/seed/${uid}_photo_${index}/200/266`,
      order: index,
      isPrimary: index === 0,
    })),
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`userPreferences/${uid}`).set({
    discoveryEnabled: true,
    interestedIn: seeks,
    genderPreference: seeks,
    minAge: 18,
    maxAge: 60,
    maxDistanceKm: 100,
  });
  // Scattered within ~10 km of the place.
  const jitter = () => (Math.random() - 0.5) * 0.15;
  await db.doc(`userLocation/${uid}`).set({
    latitude: place.lat + jitter(),
    longitude: place.lng + jitter(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

(async () => {
  if (NEW_DAY_ONLY) {
    // Istanbul midnight, simulated: the live batch ends now, so the next open
    // generates tomorrow's batch (yesterday's undecided Picks cool down).
    let expired = 0;
    for (const uid of QA_USERS) {
      const ref = db.doc(`users/${uid}/mevoraPicks/current`);
      if ((await ref.get()).exists) {
        await ref.update({refreshAtMs: Date.now() - 1});
        expired += 1;
      }
    }
    console.log(`Expired ${expired} QA batch(es). The next Picks open starts a new day.`);
    process.exit(0);
  }

  const removed = await clearPool();
  await clearBatches();
  // The QA users need something in common with the pool to clear the floor.
  for (const uid of QA_USERS) {
    await db.doc(`profiles/${uid}`).set({...SHARED, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }

  const strongPerGender = SMALL ? 3 : 24;
  const plan = [];
  for (const [gender, seeks] of [["male", "female"], ["female", "male"]]) {
    for (let i = 0; i < strongPerGender; i++) {
      plan.push({uid: `qa_pick_${gender}_strong_${String(i).padStart(2, "0")}`, gender, seeks, place: ISTANBUL, traits: SHARED, age: 24 + (i % 12)});
    }
    for (let i = 0; i < 8; i++) {
      plan.push({uid: `qa_pick_${gender}_weak_${i}`, gender, seeks, place: ISTANBUL, traits: WEAK, age: 26 + i});
    }
    for (let i = 0; i < 3; i++) {
      plan.push({uid: `qa_pick_${gender}_berlin_${i}`, gender, seeks, place: BERLIN, traits: SHARED, age: 27 + i});
    }
  }
  for (const candidate of plan) await seedCandidate(candidate);

  // Photo approval lands asynchronously through the moderation trigger.
  let approved = 0;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const snap = await db.collection("profiles").where("qaPicksPool", "==", true).get();
    approved = snap.docs.filter((doc) =>
      (doc.get("photos") ?? []).filter((photo) => photo.moderationStatus === "approved").length >= 3).length;
    if (approved >= plan.length) break;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  console.log(`Picks pool: removed ${removed}, seeded ${plan.length} (${approved} with 3 approved photos).`);
  if (approved < plan.length) {
    console.log("  WARNING: some photos are not approved yet — is the Functions emulator running?");
  }
  console.log(`  strong per gender: ${strongPerGender}${SMALL ? " (lowSupply)" : ""}, weak: 8, Berlin: 3`);
  console.log("  QA users' batches cleared: the next Picks open generates a fresh day.");
  process.exit(0);
})().catch((error) => {
  console.error("SEED FAILED:", error);
  process.exit(1);
});
