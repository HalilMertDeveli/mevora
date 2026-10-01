import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {isFaceAnchorEnforced} from "./faceAnchor/faceAnchorConfig.js";
import {computePhotoInvariants, dedupePhotos} from "./moderation/photoInvariants.js";
import {isPublishedStoragePath} from "./moderation/photoModerationLedger.js";
import {commitPhotoInvariants, loadPhotoState} from "./moderation/photoModerationService.js";
import type {PhotoRecord} from "./moderation/types.js";
import {requireOnboardingNames} from "./personName.js";
import {markLearningRequired} from "./relationshipLearning/store.js";
import {
  countApprovedPhotos,
  isAccountEligible,
  isAdultProfile,
  isFaceAnchorRequiredFor,
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

  // Counted per photo id: the same id written three times is one photo.
  const distinct = dedupePhotos((data.photos as PhotoRecord[] | undefined) ?? []);
  const approvedCount = countApprovedPhotos(distinct);
  const pendingCount = distinct.filter(
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
  // First name from the public profile, surname from the private account.
  requireOnboardingNames(data, accountSnap.data());
  validateOnboardingProfile(data);

  const age = resolveProfileAge(data);
  if (age === null || age < MIN_ONBOARDING_AGE) {
    throw new HttpsError("failed-precondition", "underage");
  }

  // Face Anchor. A member who finished onboarding before the rule applied to
  // them is not put under it by calling this again — they are prompted in the
  // app instead and come under it with their first verified photo. Read from
  // profiles/{uid}: its completion flags are server-written, unlike the copy
  // on users/{uid}.
  const anchorRequired = isFaceAnchorRequiredFor(data, isFaceAnchorEnforced());

  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (tx) => {
    const photoState = await loadPhotoState(tx, db, uid);
    if (!photoState.exists) {
      throw new HttpsError("failed-precondition", "profile-missing");
    }
    // Moderation status and the anchor come from the ledger, not from what the
    // client wrote into photos[].
    const invariants = computePhotoInvariants(photoState.photos, photoState.ledger);
    if (anchorRequired && invariants.faceAnchorPhotoIds.length === 0) {
      throw new HttpsError("failed-precondition", "face-anchor-required");
    }
    const approvedCount = countApprovedPhotos(invariants.photos);
    // Usable count already validated above. Do not block onboarding on async
    // photo moderation — users must be able to finish signup. Discovery still
    // projects only approved photos via publicProfileProjection.
    const photosReadyForDiscovery = approvedCount >= MIN_PROFILE_PHOTOS;
    const hasRejected = invariants.photos.some(
      (photo) => String(photo.moderationStatus ?? "") === "rejected",
    );
    const profileModerationStatus = hasRejected
      ? "rejected"
      : photosReadyForDiscovery
        ? "approved"
        : "pending";
    const completion = {
      uid,
      age,
      profileCompleted: true,
      onboardingCompleted: true,
      isProfileComplete: true,
      // Allow app entry immediately. Discover requires approved photos
      // (usableDiscoveryPhotos == approvedPhotos); pending stay owner-private.
      isDiscoverable: true,
      profileModerationStatus,
      onboardingStep: "complete",
      ...(anchorRequired ? {faceAnchorRequired: true} : {}),
    };
    // photos[] is no longer written back from here: the array read above the
    // transaction could be stale and would undo the reconciling trigger. A
    // profile still holding pre-ledger photos is left to that trigger, which
    // can check Storage before adopting them.
    const hasLegacyPhotos = invariants.unrecordedPhotos.some((photo) =>
      isPublishedStoragePath(uid, photo.storagePath));
    if (hasLegacyPhotos) {
      tx.update(db.doc(`profiles/${uid}`), {...completion, updatedAt: now});
    } else {
      commitPhotoInvariants(tx, db, uid, photoState, {profilePatch: completion});
    }
  });
  await db.doc(`users/${uid}`).set(
    {
      uid,
      profileCompleted: true,
      onboardingCompleted: true,
      updatedAt: now,
    },
    {merge: true},
  );

  // New members meet Relationship Learning next; their daily Picks wait for
  // the initial questions. Best effort: a failure here must never undo a
  // finished onboarding, and without the marker nobody is ever blocked.
  try {
    await markLearningRequired(db, uid);
  } catch (error) {
    logger.warn("onboarding: relationship learning marker not written", {
      error: error instanceof Error ? error.message : String(error),
    });
  }

  return {
    ok: true,
    profileCompleted: true,
    isDiscoverable: true,
    age,
  };
});
