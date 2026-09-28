#!/usr/bin/env node
/**
 * Seeds deterministic QA users into the Firebase Emulator Suite so two-user
 * runtime QA can be driven through the real Flutter app.
 *
 * These accounts sign in through the app's existing email/password form — there
 * is no separate authentication path and no injected auth state. Everything
 * downstream (AuthRepository, profile, Discover, Boost) sees an ordinary
 * Firebase session.
 *
 * Eligibility is satisfied the way the product requires it, never by weakening
 * a guard:
 *   - 3 photos, approved through users/{uid}/photoModeration/{imageId}, which is
 *     the server-owned ledger the moderation trigger reconciles against. Writing
 *     "approved" straight onto profiles/{uid}.photos is reverted by design.
 *   - real preferences, location, age and account status.
 *
 * Usage:
 *   One click: press F5 on "Mevora (development · full emulator suite)". Its
 *   preLaunchTask runs tool/ensure_emulators.ps1, which builds functions/lib,
 *   starts the emulators when they are not running yet, and runs this script
 *   with --if-missing plus tool/seedEmulatorHumorCatalog.cjs.
 *
 *   Manually, from the repo root (PowerShell):
 *
 *   1. npm --prefix functions run build
 *      firebase emulators:start --config firebase.qa.json `
 *        --project mevora-d6ed0 --only auth,firestore,functions,storage
 *
 *      Use firebase.qa.json, not the default config: its ports are the ones
 *      the app's emulator launch configuration expects. Functions must run
 *      too — the photo moderation trigger is what approves the seeded photos.
 *
 *   2. $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *      $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *      node tool/seedEmulatorQaUsers.cjs [--if-missing]
 *
 *      Without --if-missing every QA user is reset: auth account recreated,
 *      likes, matches, passes, boosts and the moderation ledger purged. With
 *      --if-missing only QA users that do not exist yet are created; existing
 *      ones, and their matches and chats, are left untouched.
 *
 *   3. flutter run --flavor development -t lib/main_development.dart `
 *        --dart-define=USE_EMULATORS=true `
 *        --dart-define=USE_AUTH_EMULATOR=true `
 *        --dart-define=USE_MOCK_HUMOR=false `
 *        --dart-define=QA_EMAIL_A=qa_user_a@mevora.test `
 *        --dart-define=QA_EMAIL_B=qa_user_b@mevora.test `
 *        --dart-define=QA_PASSWORD=<the password printed below>
 *
 *      Both emulator defines are required: USE_EMULATORS alone leaves Auth
 *      pointed at production. Do NOT pass FIREBASE_EMULATOR_HOST on Android:
 *      the app already targets 10.0.2.2, the Android emulator's alias for the
 *      host loopback. Android 16+ also needs ACCESS_LOCAL_NETWORK granted to
 *      the installed app (tool/flutter_prepare.ps1 does it); without it
 *      sign-in fails with a bare "Check your internet connection".
 */
const path = require("node:path");
const {createRequire} = require("node:module");

const PROJECT = process.env.QA_PROJECT_ID || "mevora-d6ed0";
const IF_MISSING = process.argv.slice(2).includes("--if-missing");

// Hard safety gate. Without both emulator hosts the Admin SDK would talk to
// production, and this script writes profiles and moderation decisions.
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!firestoreHost || !authHost) {
  console.error(
    "REFUSING TO RUN: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST " +
      "must both be set. This script only ever seeds the Emulator Suite.",
  );
  process.exit(1);
}
for (const [name, value] of [
  ["FIRESTORE_EMULATOR_HOST", firestoreHost],
  ["FIREBASE_AUTH_EMULATOR_HOST", authHost],
]) {
  if (!/^(127\.0\.0\.1|localhost|0\.0\.0\.0|10\.0\.2\.2):\d+$/.test(value)) {
    console.error(`REFUSING TO RUN: ${name}="${value}" is not a local emulator host.`);
    process.exit(1);
  }
}

// tool/ has no node_modules of its own: resolve firebase-admin from functions/,
// the same way tool/humorCalibrationQa.cjs does. Loaded only after the gate.
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
const auth = admin.auth();
const {FieldValue, Timestamp} = admin.firestore;

/** Emulator-only. Not a credential to any real system. Override if you like. */
const QA_PASSWORD = process.env.QA_PASSWORD || "MevoraQa!2026";

const QA_USERS = [
  {
    uid: "qa_user_a",
    email: "qa_user_a@mevora.test",
    displayName: "QA User A",
    gender: "female",
    seeksGender: "male",
    lat: 41.0082,
    lng: 28.9784,
  },
  {
    uid: "qa_user_b",
    email: "qa_user_b@mevora.test",
    displayName: "QA User B",
    gender: "male",
    seeksGender: "female",
    lat: 41.01,
    lng: 28.98,
  },
  // C exists so pass, block and account-switch can be exercised without
  // destroying the A/B match that the Boost and chat checks depend on.
  {
    uid: "qa_user_c",
    email: "qa_user_c@mevora.test",
    displayName: "QA User C",
    gender: "male",
    seeksGender: "female",
    lat: 41.012,
    lng: 28.982,
  },
  // D is the uninvolved third party for cross-user isolation checks.
  {
    uid: "qa_user_d",
    email: "qa_user_d@mevora.test",
    displayName: "QA User D",
    gender: "male",
    seeksGender: "female",
    lat: 41.014,
    lng: 28.984,
  },
];

const birthDateFor = (age) => {
  const now = new Date();
  return new Date(now.getFullYear() - age, 5, 15);
};

async function purge(uid) {
  for (const query of [
    db.collection("likes").where("fromUserId", "==", uid),
    db.collection("likes").where("toUserId", "==", uid),
    db.collection("matches").where("userIds", "array-contains", uid),
  ]) {
    const snap = await query.get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }
  for (const sub of ["passedUsers", "boosts", "boostReach", "photoModeration"]) {
    const snap = await db.collection(`users/${uid}/${sub}`).get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }
}

async function seed(user) {
  const {uid, email, displayName, gender, seeksGender, lat, lng} = user;
  await purge(uid);
  await auth.deleteUser(uid).catch(() => {});
  await auth.createUser({uid, email, password: QA_PASSWORD, emailVerified: true});

  const birthDate = birthDateFor(28);

  // The moderation ledger is the authority for photo approval. Seed it before
  // the profile so the reconciliation trigger has a decision to apply.
  for (const index of [0, 1, 2]) {
    const imageId = `${uid}_photo_${index}`;
    await db.doc(`users/${uid}/photoModeration/${imageId}`).set({
      imageId,
      status: "approved",
      reason: null,
      moderatedBy: "emulator-qa-seed",
      moderatedAt: FieldValue.serverTimestamp(),
      storagePath: `users/${uid}/profile/photos/${imageId}.jpg`,
      downloadUrl: `https://example.invalid/${imageId}.jpg`,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  await db.doc(`users/${uid}`).set({
    id: uid,
    uid,
    isBanned: false,
    isSuspended: false,
    accountStatus: "active",
    isDiscoverable: true,
    profileCompleted: true,
    onboardingCompleted: true,
    isProfileComplete: true,
    profileModerationStatus: "approved",
    moderationStatus: "approved",
    birthDate: Timestamp.fromDate(birthDate),
    lastActiveAt: FieldValue.serverTimestamp(),
  });

  await db.doc(`profiles/${uid}`).set({
    id: uid,
    uid,
    displayName,
    gender,
    birthDate: Timestamp.fromDate(birthDate),
    age: 28,
    bio: "Emulator QA fixture.",
    isDiscoverable: true,
    profileCompleted: true,
    onboardingCompleted: true,
    isProfileComplete: true,
    profileModerationStatus: "approved",
    moderationStatus: "approved",
    photos: [0, 1, 2].map((index) => ({
      id: `${uid}_photo_${index}`,
      storagePath: `users/${uid}/profile/photos/${uid}_photo_${index}.jpg`,
      downloadUrl: `https://example.invalid/${uid}_photo_${index}.jpg`,
      thumbUrl: `https://example.invalid/${uid}_photo_${index}_t.jpg`,
      order: index,
      isPrimary: index === 0,
    })),
    lastActiveAt: FieldValue.serverTimestamp(),
  });

  await db.doc(`userPreferences/${uid}`).set({
    discoveryEnabled: true,
    interestedIn: seeksGender,
    genderPreference: seeksGender,
    minAge: 18,
    maxAge: 60,
    maxDistanceKm: 100,
  });

  await db.doc(`userLocation/${uid}`).set({
    latitude: lat,
    longitude: lng,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {uid, email};
}

/** Both the sign-in account and the profile exist, so there is nothing to create. */
async function alreadySeeded(uid) {
  const account = await auth.getUser(uid).then(
    () => true,
    (error) => {
      if (error && error.code === "auth/user-not-found") {
        return false;
      }
      throw error;
    },
  );
  return account && (await db.doc(`profiles/${uid}`).get()).exists;
}

(async () => {
  console.log(
    `Seeding QA users into the emulator (project ${PROJECT}` +
      `${IF_MISSING ? ", only missing users" : ", resetting every QA user"})`,
  );
  const seeded = [];
  let kept = 0;
  for (const user of QA_USERS) {
    if (IF_MISSING && (await alreadySeeded(user.uid))) {
      kept += 1;
      continue;
    }
    seeded.push(await seed(user));
  }
  if (IF_MISSING) {
    console.log(
      `  ${seeded.length} created, ${kept} already present (left untouched)`,
    );
  }

  // The moderation trigger reconciles photos asynchronously, so poll rather
  // than sleeping a fixed amount — a single short wait reports 0/3 on a cold
  // emulator even though the reconciliation lands moments later.
  for (const {uid} of seeded) {
    let approved = 0;
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const profile = (await db.doc(`profiles/${uid}`).get()).data() ?? {};
      approved = (profile.photos ?? []).filter(
        (photo) => photo.moderationStatus === "approved",
      ).length;
      if (approved >= 3) {
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    console.log(`  ${uid}: ${approved}/3 photos approved by the moderation trigger`);
    if (approved < 3) {
      console.log("    WARNING: Discover needs 3 approved photos; is the Functions emulator running?");
    }
  }

  console.log("\nSign in through the app's normal email/password form:");
  for (const {email} of QA_USERS) {
    console.log(`  ${email}  /  ${QA_PASSWORD}`);
  }
  console.log(
    '\nLaunch: F5 on "Mevora (development · full emulator suite)", or see the ' +
      "flutter run line in this file's header.",
  );
  process.exit(0);
})().catch((error) => {
  console.error("SEED FAILED:", error);
  process.exit(1);
});
