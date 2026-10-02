import {
  isLedgerFaceAnchor,
  isSweptWhenUnreferenced,
  photoChanged,
  reconcilePhoto,
  type LedgerEntry,
} from "./photoModerationLedger.js";
import type {PhotoRecord} from "./types.js";

/**
 * What profiles/{uid}.photos must look like, given the server-owned ledger.
 *
 * profiles/{uid}.photos is a client-writable array, so every rule about it has
 * to be re-imposed after the fact. This is the one place those rules live; the
 * reconciling trigger, the face verification pipeline and onboarding completion
 * all run the same function, so they cannot drift apart.
 *
 * In order:
 *  1. An id appears once. Repeating an approved id used to count as several
 *     approved photos.
 *  2. Moderation fields and `faceAnchorVerified` come from the ledger.
 *  3. A profile that has a Face Anchor on the ledger keeps one in the array:
 *     if every anchor was removed, the most recently verified one is put back.
 *     The published object is server-owned, so it is always still there.
 *  4. An anchor that left the array while another one remains is given up:
 *     its ledger verdict is dropped, so re-adding the id yields a normal photo.
 *  5. With at least one usable anchor there is exactly one primary photo, it is
 *     an anchor, and it sits first with `order: 0`. Array position, `order` and
 *     `isPrimary` all name the same photo — the three definitions of "first"
 *     that readers of this array use.
 *
 * Pure: no I/O, so the rules are testable without Firestore.
 */

export interface PhotoInvariantResult {
  photos: PhotoRecord[];
  /** Ids of approved, verified anchors present in `photos`, in array order. */
  faceAnchorPhotoIds: string[];
  /** Ledger ids whose Face Anchor verdict must be dropped (rule 4). */
  staleAnchorIds: string[];
  /**
   * Photos with no ledger entry. The caller may be able to adopt some of them
   * (legacy pipeline-published photos) before settling for `pending`.
   */
  unrecordedPhotos: PhotoRecord[];
}

function photoId(photo: PhotoRecord): string {
  return String(photo.id ?? "");
}

function orderOf(photo: PhotoRecord, index: number): number {
  return typeof photo.order === "number" && Number.isFinite(photo.order) ? photo.order : index;
}

function millisOf(value: unknown): number {
  const stamp = value as {toMillis?: () => number} | null | undefined;
  return typeof stamp?.toMillis === "function" ? stamp.toMillis() : 0;
}

/** Rule 1. Entries with no id are left alone: they are distinct broken records, not duplicates. */
export function dedupePhotos(photos: PhotoRecord[]): PhotoRecord[] {
  const seen = new Set<string>();
  const out: PhotoRecord[] = [];
  for (const photo of photos) {
    const id = photoId(photo);
    if (id) {
      if (seen.has(id)) {
        continue;
      }
      seen.add(id);
    }
    out.push(photo);
  }
  return out;
}

/** The array element a ledger anchor is restored as (rule 3). */
function photoFromLedger(imageId: string, entry: LedgerEntry): PhotoRecord {
  return reconcilePhoto({id: imageId, order: 0, isPrimary: true}, entry);
}

export function computePhotoInvariants(
  currentPhotos: PhotoRecord[],
  ledger: Map<string, LedgerEntry>,
): PhotoInvariantResult {
  const unrecordedPhotos: PhotoRecord[] = [];
  let photos = dedupePhotos(currentPhotos).map((photo) => {
    const entry = ledger.get(photoId(photo)) ?? null;
    if (!entry) {
      unrecordedPhotos.push(photo);
    }
    return reconcilePhoto(photo, entry);
  });

  const ledgerAnchorIds = [...ledger.entries()]
    .filter(([, entry]) => isLedgerFaceAnchor(entry))
    .map(([imageId]) => imageId);
  const present = new Set(photos.map(photoId));
  let usable = ledgerAnchorIds.filter((imageId) => present.has(imageId));

  if (usable.length === 0 && ledgerAnchorIds.length > 0) {
    // Rule 3: the member removed their last anchor. Put the newest one back.
    const restoreId = [...ledgerAnchorIds].sort((a, b) =>
      millisOf(ledger.get(b)?.faceAnchor?.verifiedAt) - millisOf(ledger.get(a)?.faceAnchor?.verifiedAt) ||
      (a < b ? -1 : 1))[0];
    photos = [photoFromLedger(restoreId, ledger.get(restoreId) as LedgerEntry), ...photos];
    usable = [restoreId];
  }
  const usableSet = new Set(usable);
  const staleAnchorIds = ledgerAnchorIds.filter((imageId) => !usableSet.has(imageId));

  if (usable.length > 0) {
    // Rule 5. Honour the member's choice of primary when it is an anchor;
    // otherwise the anchor that sorts first.
    const indexed = photos.map((photo, index) => ({photo, index, order: orderOf(photo, index)}));
    const byOrder = (a: {order: number; index: number}, b: {order: number; index: number}) =>
      a.order - b.order || a.index - b.index;
    const anchors = indexed.filter(({photo}) => usableSet.has(photoId(photo))).sort(byOrder);
    const primary = anchors.find(({photo}) => photo.isPrimary === true) ?? anchors[0];
    const rest = indexed.filter((item) => item !== primary).sort(byOrder);
    photos = [primary, ...rest].map(({photo}, index) => ({
      ...photo,
      order: index,
      isPrimary: index === 0,
    }));
  }

  return {
    photos,
    faceAnchorPhotoIds: photos.map(photoId).filter((imageId) => usableSet.has(imageId)),
    staleAnchorIds,
    unrecordedPhotos,
  };
}

/**
 * Ledger entries whose `unreferencedSince` stamp disagrees with `photos`:
 * true to set it, false to clear it. `photos` is the array the invariants
 * produced, so a last anchor that was just put back counts as on the profile.
 *
 * The stamp is not a decision to delete. It records since when the photo has
 * been off the profile, and an id that returns loses it again; only a stamp
 * that has stood for the whole grace period is acted on (photoOrphanSweep.ts).
 */
export function unreferencedStampChanges(
  photos: PhotoRecord[],
  ledger: Map<string, LedgerEntry>,
): Map<string, boolean> {
  const present = new Set(photos.map(photoId));
  const changes = new Map<string, boolean>();
  for (const [imageId, entry] of ledger) {
    const unreferenced = isSweptWhenUnreferenced(entry) && !present.has(imageId);
    if (unreferenced !== (entry.unreferencedSince != null)) {
      changes.set(imageId, unreferenced);
    }
  }
  return changes;
}

/**
 * Whether a write to profiles/{uid} can have left anything to reconcile.
 *
 * An empty array is only interesting when the server knows this profile has
 * an anchor to put back (faceAnchorPhotoIds is not client-writable), or when
 * the write is the one that emptied it: the photos that just left have to be
 * marked as off the profile.
 */
export function profileNeedsReconciling(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown>,
): boolean {
  const hasPhotos = (profile: Record<string, unknown> | undefined) =>
    Array.isArray(profile?.photos) && profile.photos.length > 0;
  return hasPhotos(after) || storedFaceAnchorPhotoIds(after).length > 0 || hasPhotos(before);
}

/** True when `next` differs from `before` as an array — length, order or any field. */
export function photosChanged(before: PhotoRecord[], next: PhotoRecord[]): boolean {
  if (before.length !== next.length) {
    return true;
  }
  return before.some((photo, index) => photoChanged(photo, next[index]));
}

export function sameIds(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((id, index) => id === b[index]);
}

/** `faceAnchorPhotoIds` as stored on a profile; anything malformed reads as none. */
export function storedFaceAnchorPhotoIds(profile: Record<string, unknown> | undefined): string[] {
  const raw = profile?.faceAnchorPhotoIds;
  return Array.isArray(raw) ? raw.filter((id): id is string => typeof id === "string") : [];
}
