import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const ADULT_BIRTH_DATE = new Date(Date.UTC(1998, 5, 15));

function tinyPngBuffer() {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdrData = Buffer.alloc(13);
  ihdrData.writeUInt32BE(320, 0);
  ihdrData.writeUInt32BE(320, 4);
  ihdrData[8] = 8;
  ihdrData[9] = 2;
  const length = Buffer.alloc(4);
  length.writeUInt32BE(13, 0);
  const ihdrType = Buffer.from("IHDR");
  const ihdrCrc = Buffer.alloc(4);
  const iend = Buffer.from([
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ]);
  return Buffer.concat([signature, length, ihdrType, ihdrData, ihdrCrc, iend]);
}

export async function cleanupSmokeUsers(db, auth, emails) {
  for (const email of emails) {
    const user = await auth.getUserByEmail(email).catch(() => null);
    if (!user) continue;
    const uid = user.uid;
    await auth.deleteUser(uid).catch(() => undefined);
    const refs = [
      db.doc(`users/${uid}`),
      db.doc(`profiles/${uid}`),
      db.doc(`userPreferences/${uid}`),
      db.doc(`userSettings/${uid}`),
      db.doc(`userPrivacy/${uid}`),
      db.doc(`userLocation/${uid}`),
    ];
    await Promise.all(refs.map((ref) => ref.delete().catch(() => undefined)));
    await getStorage().bucket().deleteFiles({prefix: `users/${uid}/`}).catch(() => undefined);
  }
}

export async function seedSmokeUser(db, auth, email, label) {
  let user = await auth.getUserByEmail(email).catch(() => null);
  if (!user) {
    user = await auth.createUser({
      email,
      emailVerified: true,
      password: `Smoke!${label}9Mevora`,
      displayName: `Smoke User ${label}`,
    });
  }
  const uid = user.uid;
  await db.doc(`users/${uid}`).set({
    uid,
    email,
    accountStatus: "active",
    isActive: true,
    isBanned: false,
    isSmokeTestUser: true,
    lastActiveAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.doc(`profiles/${uid}`).set({
    uid,
    displayName: `Smoke ${label}`,
    birthDate: ADULT_BIRTH_DATE,
    age: 28,
    gender: label === "A" ? "man" : "woman",
    interestedIn: label === "A" ? "women" : "men",
    city: "Istanbul",
    education: "bachelors",
    relationshipGoal: "long_term",
    bio: "Smoke test profile for controlled production verification.",
    interests: ["music", "travel", "food"],
    lifestyleProfile: {
      smoking: "never",
      drinking: "sometimes",
      exercise: "regularly",
      pets: "none",
    },
    photos: [],
    profileCompleted: false,
    onboardingCompleted: false,
    isDiscoverable: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.doc(`userPreferences/${uid}`).set({
    preferredGender: label === "A" ? "women" : "men",
    minAge: 18,
    maxAge: 99,
    maxDistance: 100,
    discoveryEnabled: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return uid;
}

export async function uploadPendingPhoto(db, uid, index) {
  const bucket = getStorage().bucket();
  const imageId = `smoke_${index}_${Date.now()}`;
  const pendingPath = `users/${uid}/profile/pending/${imageId}.png`;
  const file = bucket.file(pendingPath);
  const png = tinyPngBuffer();
  await file.save(png, {contentType: "image/png", resumable: false});
  await db.doc(`profiles/${uid}`).set({
    photos: FieldValue.arrayUnion({
      id: imageId,
      storagePath: pendingPath,
      moderationStatus: "pending",
      order: index,
      isPrimary: index === 0,
    }),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return imageId;
}

export async function waitForApprovedPhotos(db, uid, expected = 3, timeoutMs = 120_000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const snap = await db.doc(`profiles/${uid}`).get();
    const photos = snap.data()?.photos ?? [];
    const approved = photos.filter((photo) => photo.moderationStatus === "approved");
    if (approved.length >= expected) {
      return approved;
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error(`Timed out waiting for ${expected} approved photos for ${uid}`);
}

export async function completeOnboardingViaAdmin(db, uid) {
  const snap = await db.doc(`profiles/${uid}`).get();
  const photos = snap.data()?.photos ?? [];
  const approved = photos.filter((photo) => photo.moderationStatus === "approved");
  if (approved.length < 3) {
    throw new Error("Need 3 approved photos before completion");
  }
  await db.doc(`profiles/${uid}`).set({
    profileCompleted: true,
    onboardingCompleted: true,
    isProfileComplete: true,
    isDiscoverable: true,
    profileModerationStatus: "approved",
    onboardingStep: "complete",
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.doc(`users/${uid}`).set({
    profileCompleted: true,
    onboardingCompleted: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function createActiveMatch(db, uidA, uidB) {
  const ids = [uidA, uidB].sort();
  const matchId = `${ids[0]}_${ids[1]}`;
  await db.doc(`matches/${matchId}`).set({
    id: matchId,
    userIds: ids,
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    participantNames: {[uidA]: "Smoke A", [uidB]: "Smoke B"},
    participantPhotos: {},
    unreadCounts: {[uidA]: 0, [uidB]: 0},
    isNewFor: {[uidA]: true, [uidB]: true},
    source: "smoke-test",
  }, {merge: true});
  return matchId;
}

export {getAuth, getFirestore};
