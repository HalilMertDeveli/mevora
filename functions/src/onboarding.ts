import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {
  countApprovedPhotos,
  isAccountEligible,
  isAdultProfile,
  MAX_PROFILE_PHOTOS,
  MIN_ONBOARDING_AGE,
  MIN_PROFILE_PHOTOS,
  resolveProfileAge,
} from "./profileSafety.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function requireString(value: unknown, field: string): string {
  const text = String(value ?? "").trim();
  if (!text) {
    throw new HttpsError("invalid-argument", `${field}-required`);
  }
  return text;
}

function validateOnboardingProfile(data: DocumentData): void {
  requireString(data.displayName, "displayName");
  requireString(data.gender, "gender");
  requireString(data.interestedIn, "interestedIn");
  requireString(data.city, "city");
  requireString(data.education, "education");
  requireString(data.relationshipGoal, "relationshipGoal");
  requireString(data.bio, "bio");

  const interests = (data.interests as string[]) ?? [];
  if (interests.length < 3) {
    throw new HttpsError("failed-precondition", "interests-required");
  }

  const lifestyle = (data.lifestyleProfile as DocumentData | undefined) ?? {};
  for (const field of ["smoking", "drinking", "exercise", "pets"]) {
    requireString(lifestyle[field], field);
  }

  if (!isAdultProfile(data)) {
    throw new HttpsError("failed-precondition", "underage");
  }

  const approvedCount = countApprovedPhotos(data.photos);
  const pendingCount = ((data.photos as Array<Record<string, unknown>>) ?? []).filter(
    (photo) => String(photo.moderationStatus ?? "pending") === "pending",
  ).length;
  const totalUsable = approvedCount + pendingCount;
  if (totalUsable < MIN_PROFILE_PHOTOS) {
    throw new HttpsError("failed-precondition", "photos-required");
  }
  if (totalUsable > MAX_PROFILE_PHOTOS) {
    throw new HttpsError("failed-precondition", "photos-max-exceeded");
  }
}

/// Server-side onboarding completion: 18+ gate, photo minimums, discoverability flags.
export const completeOnboarding = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const [accountSnap, profileSnap] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
  ]);
  if (!profileSnap.exists) {
    throw new HttpsError("failed-precondition", "profile-missing");
  }
  if (!isAccountEligible(accountSnap.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }

  const data = profileSnap.data() ?? {};
  validateOnboardingProfile(data);

  const age = resolveProfileAge(data);
  if (age === null || age < MIN_ONBOARDING_AGE) {
    throw new HttpsError("failed-precondition", "underage");
  }

  const photos = ((data.photos as Array<Record<string, unknown>>) ?? []);
  if (countApprovedPhotos(photos) < MIN_PROFILE_PHOTOS) {
    throw new HttpsError("failed-precondition", "photos-not-approved");
  }

  const now = FieldValue.serverTimestamp();
  await db.doc(`profiles/${uid}`).set(
    {
      uid,
      age,
      photos,
      profileCompleted: true,
      onboardingCompleted: true,
      isProfileComplete: true,
      isDiscoverable: true,
      profileModerationStatus: "approved",
      onboardingStep: "complete",
      updatedAt: now,
    },
    {merge: true},
  );
  await db.doc(`users/${uid}`).set(
    {
      uid,
      profileCompleted: true,
      onboardingCompleted: true,
      updatedAt: now,
    },
    {merge: true},
  );

  return {
    ok: true,
    profileCompleted: true,
    isDiscoverable: true,
    age,
  };
});
