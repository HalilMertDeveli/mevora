#!/usr/bin/env node
/**
 * Seeds a Mevora Picks QA world into the Firebase Emulator Suite: one viewer
 * and a candidate engineered for each Pick category, so every category, the
 * quality floor and the lifecycle can be checked through the real app.
 *
 *   picks_viewer@mevora.test     the member whose Picks you look at
 *   Kerem   Best Overall      same goal, interests and lifestyle
 *   Emre    Values Match      8/8 relationship answers aligned, same goal
 *   Can     Humor Match       calibrated Humor Lab profile close to the viewer
 *   Mert    Music Match       Spotify taste sharing most artists
 *   Arda    Nearby Match      ~2 km away and a strong match; has an active Boost
 *   Burak   Unexpected Match  nothing in common on the surface, deep match
 *   Deniz   (none)            ~1 km away but a poor match — must NOT be a Pick
 *
 * Every candidate is also a real account (same password), so a second device
 * can sign in as one of them — e.g. Can, who gets the viewer as a Pick — to
 * check a mutual like becoming a match.
 *
 * Safety: refuses to run unless both emulator hosts point at a local
 * emulator, exactly like tool/seedEmulatorQaUsers.cjs. It never touches
 * production. Photos are approved through the moderation ledger, so the
 * Functions emulator must be running.
 *
 * Usage (PowerShell, emulators already up via firebase.qa.json):
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   node tool/seedEmulatorPicksQa.cjs
 *
 * Re-running resets these accounts (likes, passes, matches, Picks batches),
 * which is how you start the Picks lifecycle over.
 */
const path = require("node:path");
const {createRequire} = require("node:module");

const PROJECT = process.env.QA_PROJECT_ID || "mevora-d6ed0";

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

/** Emulator-only. Not a credential to any real system. */
const QA_PASSWORD = process.env.QA_PASSWORD || "MevoraQa!2026";

// Istanbul, Kadıköy. Candidates sit 1-30 km away, inside the 50 km radius.
const HOME = {lat: 40.9903, lng: 29.0290};
const offset = (km, bearingDeg) => {
  const rad = (bearingDeg * Math.PI) / 180;
  return {
    lat: HOME.lat + (km / 111) * Math.cos(rad),
    lng: HOME.lng + (km / (111 * Math.cos((HOME.lat * Math.PI) / 180))) * Math.sin(rad),
  };
};

const VIEWER_INTERESTS = ["Hiking", "Jazz", "Cooking", "Photography", "Travel"];
const VIEWER_LIFESTYLE = ["nonSmoker", "earlyBird", "fitness"];
/** Relationship answers the viewer gave; aligned candidates copy them. */
const VIEWER_ANSWERS = {
  rq_001: "a", rq_002: "b", rq_003: "c", rq_004: "a",
  rq_005: "b", rq_006: "c", rq_007: "a", rq_008: "b",
};
const HUMOR_DIMS = [
  "sarcasm", "absurd", "silly", "romantic", "dark", "meme",
  "dry", "wordplay", "situational", "cringe", "teasing",
];
const humorVector = (overrides) =>
  Object.fromEntries(HUMOR_DIMS.map((dim) => [dim, overrides[dim] ?? 45]));
const VIEWER_HUMOR = humorVector({absurd: 86, dark: 80, dry: 72, wordplay: 66});
const SHARED_ARTISTS = ["4Z8W4fKeB5YxbusRsdQVPb", "0oSGxfWSnnOXhD2fKuz2Gy", "3WrFJ7ztbogyGnTHbHJFl2", "1dfeR4HaWDbWqFHLkxsg1d", "6olE6TJLqED3rqDCT0FyPh"];
const SHARED_TRACKS = ["t_teardrop", "t_heroes", "t_paranoid_android", "t_come_together"];

const PEOPLE = [
  {
    uid: "picks_viewer",
    email: "picks_viewer@mevora.test",
    displayName: "Selin",
    gender: "female",
    seeks: "male",
    at: HOME,
    interests: VIEWER_INTERESTS,
    lifestyle: VIEWER_LIFESTYLE,
    goal: "longTerm",
    answers: VIEWER_ANSWERS,
    humor: VIEWER_HUMOR,
    music: {artists: [...SHARED_ARTISTS, "a_viewer_1", "a_viewer_2"], tracks: [...SHARED_TRACKS, "t_viewer_1"]},
  },
  {
    uid: "picks_best",
    email: "picks_best@mevora.test",
    displayName: "Kerem",
    at: offset(12, 40),
    interests: VIEWER_INTERESTS,
    lifestyle: VIEWER_LIFESTYLE,
    goal: "longTerm",
  },
  {
    uid: "picks_values",
    email: "picks_values@mevora.test",
    displayName: "Emre",
    at: offset(18, 200),
    interests: ["Hiking", "Jazz", "Cooking", "Books"],
    lifestyle: VIEWER_LIFESTYLE,
    goal: "longTerm",
    answers: VIEWER_ANSWERS,
  },
  {
    uid: "picks_humor",
    email: "picks_humor@mevora.test",
    displayName: "Can",
    at: offset(15, 300),
    interests: ["Jazz", "Cinema", "Travel"],
    lifestyle: ["nonSmoker", "nightOwl"],
    goal: "longTerm",
    answers: {rq_001: "a", rq_002: "b", rq_003: "c"},
    humor: humorVector({absurd: 89, dark: 77, dry: 74, wordplay: 62}),
  },
  {
    uid: "picks_music",
    email: "picks_music@mevora.test",
    displayName: "Mert",
    at: offset(22, 120),
    interests: ["Concerts", "Jazz", "Travel"],
    lifestyle: ["nonSmoker", "nightOwl"],
    goal: "longTerm",
    music: {artists: [...SHARED_ARTISTS, "a_mert_1"], tracks: [...SHARED_TRACKS, "t_mert_1"]},
  },
  {
    uid: "picks_nearby",
    email: "picks_nearby@mevora.test",
    displayName: "Arda",
    at: offset(2, 90),
    interests: ["Hiking", "Jazz", "Cooking"],
    lifestyle: ["nonSmoker", "earlyBird"],
    goal: "longTerm",
    boosted: true,
  },
  {
    uid: "picks_unexpected",
    email: "picks_unexpected@mevora.test",
    displayName: "Burak",
    at: offset(20, 250),
    interests: ["Gaming", "Football", "Cars"],
    lifestyle: VIEWER_LIFESTYLE,
    goal: "longTerm",
    answers: VIEWER_ANSWERS,
  },
  {
    uid: "picks_weak",
    email: "picks_weak@mevora.test",
    displayName: "Deniz",
    at: offset(1, 180),
    interests: ["Clubbing"],
    lifestyle: ["smoker", "nightOwl"],
    goal: "casual",
  },
];

async function deleteAll(query) {
  const snap = await query.get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
}

async function purge(uid) {
  await deleteAll(db.collection("likes").where("fromUserId", "==", uid));
  await deleteAll(db.collection("likes").where("toUserId", "==", uid));
  await deleteAll(db.collection("matches").where("userIds", "array-contains", uid));
  for (const sub of ["passedUsers", "boosts", "boostReach", "photoModeration", "mevoraPicks", "blockedUsers"]) {
    await deleteAll(db.collection(`users/${uid}/${sub}`));
  }
  await deleteAll(db.collection("blocks").where("blockerId", "==", uid));
  await deleteAll(db.collection("blocks").where("blockedUserId", "==", uid));
}

async function seed(person) {
  const {uid, email, displayName} = person;
  const gender = person.gender ?? "male";
  const seeks = person.seeks ?? "female";
  await purge(uid);
  await auth.deleteUser(uid).catch(() => {});
  await auth.createUser({uid, email, password: QA_PASSWORD, emailVerified: true, displayName});
  const age = 27 + (uid.length % 5);
  const birthDate = new Date(new Date().getFullYear() - age, 3, 12);
  const now = Timestamp.now();

  for (const index of [0, 1, 2]) {
    const imageId = `${uid}_photo_${index}`;
    await db.doc(`users/${uid}/photoModeration/${imageId}`).set({
      imageId,
      status: "approved",
      reason: null,
      moderatedBy: "emulator-picks-seed",
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
    lastActiveAt: now,
  });
  await db.doc(`profiles/${uid}`).set({
    id: uid,
    uid,
    displayName,
    gender,
    age,
    bio: "Mevora Picks QA fixture.",
    city: "İstanbul",
    interests: person.interests,
    lifestyle: person.lifestyle,
    relationshipGoal: person.goal,
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
    lastActiveAt: now,
    updatedAt: now,
  });
  await db.doc(`userPreferences/${uid}`).set({
    discoveryEnabled: true,
    interestedIn: seeks,
    genderPreference: seeks,
    minAge: 18,
    maxAge: 60,
    maxDistanceKm: 100,
  });
  await db.doc(`userLocation/${uid}`).set({
    latitude: person.at.lat,
    longitude: person.at.lng,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`userSettings/${uid}`).set({languageCode: "tr"}, {merge: true});

  if (person.answers) {
    await db.doc(`users/${uid}/relationshipMatch/summary`).set({
      answers: person.answers,
      answeredIds: Object.keys(person.answers).sort(),
      answerCount: Object.keys(person.answers).length,
      questionIds: Object.keys(person.answers).slice(0, 3),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await db.doc(`users/${uid}/relationshipMatch/summary`).delete();
  }

  if (person.humor) {
    await db.doc(`users/${uid}/humor/summary`).set({
      vector: person.humor,
      confidence: 0.8,
      interactionCount: 20,
      exploredCategories: HUMOR_DIMS,
      version: 1,
      lastUpdatedAt: FieldValue.serverTimestamp(),
    });
    await db.doc(`users/${uid}/humor/calibration`).set({version: 1, completedCount: 15});
  } else {
    await deleteAll(db.collection(`users/${uid}/humor`));
  }

  if (person.music) {
    await db.doc(`users/${uid}/music/summary`).set({
      spotifyConnected: true,
      displayName,
      musicProfile: {
        artistIds: person.music.artists,
        trackIds: person.music.tracks,
        genres: [{name: "trip hop"}, {name: "art rock"}, {name: "jazz"}],
        recentTrackIds: [],
        recentArtistIds: [],
        playlistTrackIds: [],
      },
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await db.doc(`users/${uid}/music/summary`).delete();
  }

  if (person.boosted) {
    const expiresAt = Timestamp.fromMillis(Date.now() + 6 * 24 * 60 * 60 * 1000);
    await db.doc(`users/${uid}/boosts/picks_qa_boost`).set({
      userId: uid,
      status: "active",
      startedAt: now,
      expiresAt,
      source: "emulator-picks-seed",
    });
  }
}

(async () => {
  console.log(`Seeding the Mevora Picks QA world into the emulator (project ${PROJECT})`);
  for (const person of PEOPLE) {
    await seed(person);
  }
  for (const {uid} of PEOPLE) {
    let approved = 0;
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const profile = (await db.doc(`profiles/${uid}`).get()).data() ?? {};
      approved = (profile.photos ?? []).filter((p) => p.moderationStatus === "approved").length;
      if (approved >= 3) break;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
    console.log(`  ${uid}: ${approved}/3 photos approved`);
  }
  console.log("\nSign in through the app's email/password form (password for all):");
  console.log(`  ${QA_PASSWORD}`);
  for (const {email, displayName} of PEOPLE) {
    console.log(`  ${email}  (${displayName})`);
  }
  process.exit(0);
})().catch((error) => {
  console.error("SEED FAILED:", error);
  process.exit(1);
});
