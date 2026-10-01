import {Timestamp, type Firestore, type Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {MIN_PROFILE_PHOTOS} from "../profileSafety.js";
import {dedupePhotos} from "./photoInvariants.js";
import {isLedgerFaceAnchor, isRemovedByMember, ledgerRef, type LedgerEntry} from "./photoModerationLedger.js";
import {commitPhotoInvariants, loadPhotoState, type PhotoState} from "./photoModerationService.js";
import {PHOTO_VARIANTS, variantPath} from "./photoVariants.js";
import {PROCESSING_STALE_MS, type PhotoRecord} from "./types.js";

/**
 * A member removes one of their own profile photos — for good.
 *
 * Removing a photo used to be nothing but a client rewrite of
 * profiles/{uid}.photos. The Storage rules deny clients every write under
 * photos/ and thumbs/, so the published original, its display variants and the
 * ledger entry all stayed behind, the original still reachable through its
 * tokenised download URL.
 *
 * Why an explicit call rather than a reaction to the array changing: an id
 * missing from the array is not a decision to delete. The reconciling trigger
 * puts a removed last Face Anchor back, and a stale whole-array client write
 * can drop a photo the next write restores. A trigger that deleted the object
 * on such an event would destroy a photo the profile is about to show again.
 * Here the member asked, the rules are checked against the profile as one
 * transaction saw it, and only then is anything deleted.
 *
 * In order:
 *  1. One transaction refuses the request, or takes the photo out of the array,
 *     re-imposes the photo invariants (photoInvariants.ts) on the rest and
 *     deletes the ledger entry.
 *  2. The objects are deleted: the published original, both variants and the
 *     pending upload, which publishing leaves in place.
 *
 * The ledger entry goes in the same transaction as the array entry because it
 * is what tells the moderation pipeline the photo still exists: a decision
 * that was on its way when the member deleted the photo finds no entry and is
 * dropped (setPhotoModerationStatus) instead of writing the photo back.
 *
 * A photo that moderation rejected or is holding for review leaves the
 * profile but keeps its ledger entry and whatever is stored: the entry is the
 * moderation record (and what stops the id being uploaded again), and a
 * reviewer still needs the image. The entry is stamped `removedByMemberAt`, so
 * whatever is decided about the photo later is recorded without the photo
 * being put back — and a reviewer who approves it finishes this deletion
 * (admin/photos/photoReview.ts, through queueHeldPhotoDeletion below).
 *
 * The array rewrite older clients perform keeps working and keeps leaking; it
 * is not turned into a deletion for the reasons above.
 */

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const EXTENSIONS = ["jpg", "png", "webp"] as const;
const DELETE_ATTEMPTS = 2;

/** Minimal Storage surface this module needs; the Admin SDK bucket satisfies it. */
export interface PhotoDeletionBucket {
  file(path: string): {delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>};
}

export interface DeleteProfilePhotoDeps {
  db: Firestore;
  bucket: () => PhotoDeletionBucket;
  now: () => number;
}

/**
 * `complete` — nothing of the photo is stored any more.
 * `retained` — moderation keeps the record (rejected or under review).
 * `incomplete` — an object could not be deleted; calling again retries.
 */
export type PhotoCleanup = "complete" | "retained" | "incomplete";

export interface DeleteProfilePhotoResult {
  photoId: string;
  /** False when the photo was not on the profile; the cleanup still ran. */
  removed: boolean;
  cleanup: PhotoCleanup;
}

function photoId(photo: PhotoRecord): string {
  return String(photo.id ?? "");
}

function millisOf(value: unknown): number {
  const stamp = value as {toMillis?: () => number} | null | undefined;
  return typeof stamp?.toMillis === "function" ? stamp.toMillis() : 0;
}

function refused(reason: string): HttpsError {
  return new HttpsError("failed-precondition", reason);
}

/**
 * The array without `imageId`: display order with gaps closed and, if the
 * primary photo was the one removed, the first remaining photo in its place.
 * The same result as the app's PhotoPolicy.normalize for a profile without a
 * Face Anchor; with one, computePhotoInvariants decides the primary.
 */
export function photosWithout(photos: PhotoRecord[], imageId: string): PhotoRecord[] {
  const remaining = photos
    .map((photo, index) => ({
      photo,
      index,
      order: typeof photo.order === "number" && Number.isFinite(photo.order) ? photo.order : index,
    }))
    .filter(({photo}) => photoId(photo) !== imageId)
    .sort((a, b) => a.order - b.order || a.index - b.index);
  const hasPrimary = remaining.some(({photo}) => photo.isPrimary === true);
  return remaining.map(({photo}, index) => ({
    ...photo,
    order: index,
    isPrimary: hasPrimary ? photo.isPrimary === true : index === 0,
  }));
}

/** Every place the bytes of this photo can be. Never the quarantine prefix. */
export function photoObjectPaths(uid: string, imageId: string, ledgerPath?: string | null): string[] {
  const root = `users/${uid}/profile`;
  const paths = new Set<string>();
  for (const extension of EXTENSIONS) {
    paths.add(`${root}/photos/${imageId}.${extension}`);
    paths.add(`${root}/pending/${imageId}.${extension}`);
  }
  for (const spec of PHOTO_VARIANTS) {
    paths.add(variantPath(uid, imageId, spec.name));
  }
  // Where uploads and thumbnails lived before pending/ and the variants.
  paths.add(`${root}/${imageId}`);
  paths.add(`${root}/thumbs/${imageId}`);
  if (typeof ledgerPath === "string" && ledgerPath.startsWith(`${root}/`)) {
    paths.add(ledgerPath);
  }
  return [...paths];
}

async function deleteObject(bucket: PhotoDeletionBucket, path: string): Promise<boolean> {
  for (let attempt = 1; attempt <= DELETE_ATTEMPTS; attempt += 1) {
    try {
      await bucket.file(path).delete({ignoreNotFound: true});
      return true;
    } catch {
      // Tried again below; the caller reports what is left.
    }
  }
  return false;
}

/**
 * Deletes everything photoObjectPaths names. Resolves to the number of objects
 * that could not be deleted; calling again retries them.
 */
export async function deletePhotoObjects(
  bucket: PhotoDeletionBucket,
  uid: string,
  imageId: string,
  ledgerPath?: string | null,
): Promise<number> {
  const paths = photoObjectPaths(uid, imageId, ledgerPath);
  const deleted = await Promise.all(paths.map((path) => deleteObject(bucket, path)));
  return deleted.filter((ok) => !ok).length;
}

/**
 * The Firestore half of deleting a photo whose entry moderation was keeping,
 * queued on the caller's transaction: the entry goes, and so does the array
 * element if a stale whole-array write has put the id back since the member
 * removed it. `state` must have been read in that transaction.
 *
 * For a reviewer's approval of a photo the member already removed: the
 * decision is the last thing the entry was kept for. No minimum and no Face
 * Anchor check here — the member's request passed them when it was made.
 */
export function queueHeldPhotoDeletion(
  tx: Transaction,
  db: Firestore,
  uid: string,
  state: PhotoState,
  imageId: string,
): void {
  // As in deleteProfilePhoto: gone from the ledger the invariants see.
  state.ledger.delete(imageId);
  const photos = dedupePhotos(state.photos);
  if (photos.some((photo) => photoId(photo) === imageId)) {
    commitPhotoInvariants(tx, db, uid, state, {photos: photosWithout(photos, imageId)});
  }
  tx.delete(ledgerRef(db, uid, imageId));
}

function keptByModeration(entry: LedgerEntry | null): boolean {
  return entry?.status === "rejected" || entry?.status === "manual_review";
}

export async function deleteProfilePhoto(
  deps: DeleteProfilePhotoDeps,
  uid: string,
  input: {photoId?: unknown},
): Promise<DeleteProfilePhotoResult> {
  const {db} = deps;
  const imageId = typeof input.photoId === "string" ? input.photoId.trim() : "";
  if (!ID_PATTERN.test(imageId)) {
    throw new HttpsError("invalid-argument", "photo-id-required");
  }
  const nowMs = deps.now();

  const {removed, entry} = await db.runTransaction(async (tx) => {
    const state = await loadPhotoState(tx, db, uid);
    const photos = dedupePhotos(state.photos);
    const onProfile = photos.some((photo) => photoId(photo) === imageId);
    const entry = state.ledger.get(imageId) ?? null;

    // The pipeline is on this photo right now and writes its result back by
    // id, so a photo deleted under it would return. Past the stale mark that
    // run is dead, and the photo can go.
    if (entry?.status === "processing" && nowMs - millisOf(entry.moderatedAt) < PROCESSING_STALE_MS) {
      throw refused("photo_processing");
    }
    if (onProfile && state.profile.profileCompleted === true && photos.length <= MIN_PROFILE_PHOTOS) {
      throw refused("photo_min_required");
    }
    // Judged on the ledger, not on the array: an anchor a stale write dropped
    // is still the member's anchor, and reconciliation is about to restore it.
    if (isLedgerFaceAnchor(entry)) {
      const present = new Set(photos.map(photoId));
      const anotherAnchor = [...state.ledger].some(([otherId, other]) =>
        otherId !== imageId && present.has(otherId) && isLedgerFaceAnchor(other));
      if (!anotherAnchor) {
        throw refused("photo_last_face_anchor");
      }
    }
    const kept = keptByModeration(entry);
    if (!kept) {
      // Gone from the ledger the invariants are computed on, so it is neither
      // restored nor updated as a stale anchor in the transaction deleting it.
      state.ledger.delete(imageId);
    }
    if (onProfile) {
      commitPhotoInvariants(tx, db, uid, state, {photos: photosWithout(photos, imageId)});
    }
    if (entry && !kept) {
      tx.delete(ledgerRef(db, uid, imageId));
    } else if (entry && !isRemovedByMember(entry)) {
      // The record stays; this says the photo does not. `updatedAt` is left
      // alone: it is the entry's place in the review queue.
      tx.update(ledgerRef(db, uid, imageId), {removedByMemberAt: Timestamp.fromMillis(nowMs)});
    }
    return {removed: onProfile, entry};
  });

  if (keptByModeration(entry)) {
    return {photoId: imageId, removed, cleanup: "retained"};
  }

  const failures = await deletePhotoObjects(deps.bucket(), uid, imageId, entry?.storagePath);
  if (failures > 0) {
    logger.error("Removed profile photo still has stored objects", {uid, imageId, failures});
    return {photoId: imageId, removed, cleanup: "incomplete"};
  }
  logger.info("Profile photo deleted by its owner", {uid, imageId, removed});
  return {photoId: imageId, removed, cleanup: "complete"};
}
