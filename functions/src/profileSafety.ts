import {Timestamp, type DocumentData} from "firebase-admin/firestore";
import {toPublicMusicCard} from "./spotifyMusicProfile.js";

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

export type EffectiveAccountStatus = "active" | "suspended" | "banned" | "deleted";

function millisOf(value: unknown): number | null {
  if (value instanceof Timestamp) {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  const withMillis = value as {toMillis?: () => number} | null | undefined;
  if (withMillis && typeof withMillis.toMillis === "function") {
    return withMillis.toMillis();
  }
  return null;
}

/**
 * The account's standing right now.
 *
 * `users/{uid}.accountStatus` is canonical. The legacy `isBanned` /
 * `isSuspended` booleans are still honoured so nothing that predates the
 * canonical field loosens: either flag restricts on its own.
 *
 * A suspension carrying `suspendedUntil` ends by itself once that instant
 * passes — eligibility does not wait for the expiry sweep to rewrite the
 * document. A suspension with no end date lasts until an admin restores it.
 */
export function effectiveAccountStatus(
  account: DocumentData | undefined,
  nowMs: number = Date.now(),
): EffectiveAccountStatus {
  if (!account) {
    return "active";
  }
  const status = String(account.accountStatus ?? "active");
  if (status === "deleted") {
    return "deleted";
  }
  if (status === "banned" || account.isBanned === true) {
    return "banned";
  }
  if (status === "suspended" || account.isSuspended === true) {
    const until = millisOf(account.suspendedUntil);
    if (until !== null && until <= nowMs) {
      return "active";
    }
    return "suspended";
  }
  return "active";
}

export function isAccountEligible(account: DocumentData | undefined, nowMs: number = Date.now()): boolean {
  return effectiveAccountStatus(account, nowMs) === "active";
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

/**
 * Approved means explicitly approved. A missing moderationStatus used to
 * default to "approved", so a client could publish an unmoderated photo just by
 * omitting the field — and the moderation guard's before/after status
 * comparison saw no change and let it stand. Unmoderated now means pending.
 */
export function approvedPhotos(photos: unknown): Array<Record<string, unknown>> {
  return ((photos as Array<Record<string, unknown>>) ?? []).filter(
    (photo) => String(photo.moderationStatus ?? "pending") === "approved",
  );
}

/**
 * Photos that may appear in Discover. Only moderated (approved) photos —
 * pending Storage objects are owner-private and must not be shared via feed URLs.
 */
export function usableDiscoveryPhotos(photos: unknown): Array<Record<string, unknown>> {
  return approvedPhotos(photos);
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
  // `publicMusic` is the only Spotify data that reaches another member, and
  // toPublicMusicCard rebuilds it field by field. The private taste in
  // users/{uid}/music/summary — recently played, playlist tracks, the
  // fingerprint — is never part of a profile projection.
  const publicMusic = toPublicMusicCard(data.publicMusic);
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
    ...(publicMusic ? {publicMusic} : {}),
  };
}

/**
 * Discover feed projection: approved photos only (same as public card photos).
 */
export function discoveryProfileProjection(data: DocumentData): Record<string, unknown> {
  return publicProfileProjection(data);
}
