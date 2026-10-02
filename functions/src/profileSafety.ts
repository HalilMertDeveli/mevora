import {Timestamp, type DocumentData} from "firebase-admin/firestore";
import {toPublicMusicCard} from "./spotifyMusicProfile.js";

export const MIN_ONBOARDING_AGE = 18;
export const MIN_PROFILE_PHOTOS = 3;
export const MAX_PROFILE_PHOTOS = 6;

const DAY_MS = 86_400_000;

/**
 * The calendar day a stored date of birth stands for, as that day's midnight
 * in UTC.
 *
 * The app stores midnight of the day the member picked on the member's own
 * clock: 11 April picked in Istanbul is 10 April 21:00 UTC. Read with UTC
 * fields as it stands, that is the day before for everyone east of UTC. A
 * local midnight is never more than twelve hours from the UTC midnight of the
 * same day on any clock from UTC-12 to UTC+12, so the nearest UTC midnight is
 * the day that was picked. A date already stored as UTC midnight is its own
 * nearest one, and comes back unchanged.
 *
 * At exactly twelve hours the later day is taken: that instant is UTC+12
 * (Auckland in winter, Fiji), not the uninhabited UTC-12. Beyond UTC+12 —
 * UTC+12:45 to UTC+14 — the day before is the nearer one and is what comes
 * back, as it did before this rule; see docs/PROFILE_BIRTH_DATE_PRIVACY.md.
 */
export function birthCalendarDate(birthDate: Date): Date {
  const millis = birthDate.getTime();
  const intoDay = ((millis % DAY_MS) + DAY_MS) % DAY_MS;
  const dayStart = millis - intoDay;
  return new Date(intoDay * 2 >= DAY_MS ? dayStart + DAY_MS : dayStart);
}

/**
 * Whole years from the day the member picked to `today`, both read as
 * calendar days in UTC — the server's day, whatever zone the process is in.
 */
export function ageFromBirthDate(birthDate: Date, today: Date = new Date()): number {
  const born = birthCalendarDate(birthDate);
  let years = today.getUTCFullYear() - born.getUTCFullYear();
  const monthDelta = today.getUTCMonth() - born.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && today.getUTCDate() < born.getUTCDate())) {
    years -= 1;
  }
  return years;
}

/**
 * The age a profile document stands for.
 *
 * profiles/{uid} carries `age` only: the server writes it from the member's
 * private date of birth (profileAge.ts) and a client cannot change it. A
 * `birthDate` is read here solely for profiles written before the date moved
 * to users/{uid}, until the backfill has been run; the rules no longer let a
 * client put one on a profile.
 */
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
  return isAdultProfile(data) && faceAnchorSatisfied(data);
}

/**
 * Whether this profile must have a Face Anchor to be completed.
 *
 * A profile already under the rule stays under it. Otherwise the rule applies
 * to a profile that has not finished onboarding, while enforcement is on. A
 * member who finished before the rule applied to them is not put under it by
 * anything they do except verifying a photo. `profileCompleted` is read from
 * profiles/{uid}, where only the server writes it.
 */
export function isFaceAnchorRequiredFor(profile: DocumentData | undefined, enforced: boolean): boolean {
  if (profile?.faceAnchorRequired === true) {
    return true;
  }
  return enforced && profile?.profileCompleted !== true;
}

/**
 * Whether a profile meets the Face Anchor rule: the photo other members see
 * first is one the server verified against the live account owner.
 *
 * Reads only fields a client cannot write. `faceAnchorRequired` and
 * `faceAnchorPhotoIds` are absent from the profile rules' allowlists and are
 * written by the server alone, from the moderation ledger.
 *
 * A profile that was never put under the rule (completed before Face Anchor
 * existed, or while enforcement was off) passes: its photos are not treated as
 * verified, and it is not hidden for lacking a check it was never offered.
 *
 * Readers of photos[] disagree on what "first" means — array position, lowest
 * `order`, the `isPrimary` flag — and all three are client-written until the
 * reconciling trigger has run. So every candidate for "first" must be an
 * anchor: whatever a reader picks, it is a verified photo.
 */
export function faceAnchorSatisfied(data: DocumentData | undefined): boolean {
  if (data?.faceAnchorRequired !== true) {
    return true;
  }
  const anchorIds = new Set(
    (Array.isArray(data.faceAnchorPhotoIds) ? data.faceAnchorPhotoIds : [])
      .filter((id: unknown): id is string => typeof id === "string" && id.length > 0),
  );
  const approved = approvedPhotos(data.photos);
  if (anchorIds.size === 0 || approved.length === 0) {
    return false;
  }
  const orderOf = (photo: Record<string, unknown>, index: number) =>
    typeof photo.order === "number" ? photo.order : index;
  let lowest = approved[0];
  let lowestOrder = orderOf(lowest, 0);
  approved.forEach((photo, index) => {
    if (orderOf(photo, index) < lowestOrder) {
      lowest = photo;
      lowestOrder = orderOf(photo, index);
    }
  });
  const firsts = [approved[0], lowest, ...approved.filter((photo) => photo.isPrimary === true)];
  return firsts.every((photo) => anchorIds.has(String(photo.id ?? "")));
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
    cardUrl: photo.cardUrl ?? null,
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
