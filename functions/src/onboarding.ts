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

  // Preferred source: structured `lifestyleProfile` map.
  // Fallback source (legacy / older clients / schema drift): `lifestyle` tag list.
  const lifestyleProfile = (data.lifestyleProfile as DocumentData | undefined) ?? {};
  const lifestyleTags = Array.isArray(data.lifestyle) ? data.lifestyle : [];
  const lifestyleFromTags: Record<string, string> = {};

  for (const tag of lifestyleTags) {
    if (typeof tag !== "string") {
      continue;
    }
    const [key, ...rest] = tag.split(":");
    const value = rest.join(":");
    if (!key || !value) {
      continue;
    }
    lifestyleFromTags[key] = value;
  }

  for (const field of ["smoking", "drinking", "exercise", "pets"]) {
    const value =
      (lifestyleProfile as Record<string, unknown>)[field] ??
      lifestyleFromTags[field];
    requireString(value, field);
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
  const approvedCount = countApprovedPhotos(photos);
  // Usable count already validated above. Do not block onboarding on async
  // photo moderation — users must be able to finish signup. Discovery still
  // projects only approved photos via publicProfileProjection.
  const photosReadyForDiscovery = approvedCount >= MIN_PROFILE_PHOTOS;
  const hasRejected = photos.some(
    (photo) => String(photo.moderationStatus ?? "") === "rejected",
  );
  const profileModerationStatus = hasRejected
    ? "rejected"
    : photosReadyForDiscovery
      ? "approved"
      : "pending";

  const now = FieldValue.serverTimestamp();
  await db.doc(`profiles/${uid}`).set(
    {
      uid,
      age,
      photos,
      profileCompleted: true,
      onboardingCompleted: true,
      isProfileComplete: true,
  // Allow app entry immediately. Discover uses usableDiscoveryPhotos so pending
  // photos with download URLs remain visible while moderation completes.
  isDiscoverable: true,
      profileModerationStatus,
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
