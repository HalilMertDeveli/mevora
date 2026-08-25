import {Timestamp, type DocumentData} from "firebase-admin/firestore";

export const MIN_ONBOARDING_AGE = 18;
export const MIN_PROFILE_PHOTOS = 3;
export const MAX_PROFILE_PHOTOS = 6;

export function ageFromBirthDate(birthDate: Date): number {
  const today = new Date();
  let years = today.getFullYear() - birthDate.getFullYear();
  const monthDelta = today.getMonth() - birthDate.getMonth();
  if (monthDelta < 0 || (monthDelta === 0 && today.getDate() < birthDate.getDate())) {
    years -= 1;
  }
  return years;
}

export function resolveProfileAge(data: DocumentData | undefined): number | null {
  if (!data) {
    return null;
  }
  const birthDate = data.birthDate;
  if (birthDate instanceof Timestamp) {
    return ageFromBirthDate(birthDate.toDate());
  }
  const age = Number(data.age ?? 0);
  return age > 0 ? age : null;
}

export function isAdultProfile(data: DocumentData | undefined): boolean {
  const age = resolveProfileAge(data);
  return age !== null && age >= MIN_ONBOARDING_AGE;
}

export function isAccountEligible(account: DocumentData | undefined): boolean {
  if (!account) {
    return true;
  }
  if (account.isBanned === true) {
    return false;
  }
  const status = String(account.accountStatus ?? "active");
  return status !== "banned" && status !== "suspended" && status !== "deleted";
}

export function isProfileDiscoverable(data: DocumentData | undefined): boolean {
  if (!data) {
    return false;
  }
  if (data.isDiscoverable !== true || data.profileCompleted !== true) {
    return false;
  }
  const moderationStatus = String(data.profileModerationStatus ?? data.moderationStatus ?? "approved");
  if (moderationStatus === "suspended" || moderationStatus === "rejected" || moderationStatus === "manual_review") {
    return false;
  }
  return isAdultProfile(data);
}

export function approvedPhotos(photos: unknown): Array<Record<string, unknown>> {
  return ((photos as Array<Record<string, unknown>>) ?? []).filter(
    (photo) => String(photo.moderationStatus ?? "approved") === "approved",
  );
}

/**
 * Photos that can appear in Discover while moderation is still async.
 * Rejected photos are excluded. Pending/processing need a viewable URL.
 */
export function usableDiscoveryPhotos(photos: unknown): Array<Record<string, unknown>> {
  return ((photos as Array<Record<string, unknown>>) ?? []).filter((photo) => {
    const status = String(photo.moderationStatus ?? "pending");
    if (status === "rejected") {
      return false;
    }
    if (status === "approved") {
      return true;
    }
    return Boolean(photo.downloadUrl || photo.thumbUrl);
  });
}

export function countApprovedPhotos(photos: unknown): number {
  return approvedPhotos(photos).length;
}

export function countUsableDiscoveryPhotos(photos: unknown): number {
  return usableDiscoveryPhotos(photos).length;
}

function projectPhotos(photos: Array<Record<string, unknown>>): Array<Record<string, unknown>> {
  return photos.map((photo) => ({
    id: photo.id,
    downloadUrl: photo.downloadUrl ?? null,
    thumbUrl: photo.thumbUrl ?? null,
    order: photo.order ?? 0,
    isPrimary: photo.isPrimary ?? false,
    moderationStatus: photo.moderationStatus ?? "pending",
  }));
}

/** Strict public card: only fully approved photos. */
export function publicProfileProjection(data: DocumentData): Record<string, unknown> {
  return {
    uid: data.uid,
    displayName: data.displayName ?? "",
    age: resolveProfileAge(data),
    gender: data.gender ?? null,
    bio: data.bio ?? null,
    photos: projectPhotos(approvedPhotos(data.photos)),
    interests: data.interests ?? [],
    relationshipGoal: data.relationshipGoal ?? null,
    city: data.city ?? null,
    isVerified: data.isVerified === true,
  };
}

/**
 * Discover feed projection: include pending/processing photos that already have
 * a download URL so newly onboarded users are visible before async moderation.
 */
export function discoveryProfileProjection(data: DocumentData): Record<string, unknown> {
  return {
    ...publicProfileProjection(data),
    photos: projectPhotos(usableDiscoveryPhotos(data.photos)),
  };
}
