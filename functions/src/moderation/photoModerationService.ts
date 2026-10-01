import {randomUUID} from "node:crypto";
import {FieldValue, Timestamp, type Firestore, type Transaction} from "firebase-admin/firestore";
import type {Bucket} from "@google-cloud/storage";
import {logger} from "firebase-functions";
import {moderatePhotoBuffer} from "./manualModerationProvider.js";
import {
  MAX_PROCESSING_ATTEMPTS,
  PROCESSING_STALE_MS,
  type PhotoModerationStatus,
  type PhotoRecord,
} from "./types.js";
import {
  backfillLegacyApproval,
  isPublishedStoragePath,
  ledgerCollection,
  ledgerEntryFromData,
  ledgerRef,
  writeLedgerEntry,
  type LedgerEntry,
} from "./photoModerationLedger.js";
import {
  computePhotoInvariants,
  photosChanged,
  sameIds,
  storedFaceAnchorPhotoIds,
} from "./photoInvariants.js";
import {
  PHOTO_CACHE_CONTROL,
  firebaseDownloadUrl,
  publishPhotoVariants,
} from "./photoVariants.js";

function extensionForContentType(contentType: string | undefined): string {
  const lower = String(contentType ?? "").toLowerCase();
  if (lower.includes("png")) return "png";
  if (lower.includes("webp")) return "webp";
  return "jpg";
}

function photosFrom(data: Record<string, unknown> | undefined): PhotoRecord[] {
  return ((data?.photos as PhotoRecord[] | undefined) ?? []).map((photo) => ({...photo}));
}

/**
 * profiles/{uid}.photos is an array of maps, and Firestore rejects a FieldValue
 * sentinel anywhere inside an array element. Resolve every timestamp in the
 * patch (moderatedAt, lastProcessingAttempt) to a concrete server-clock
 * Timestamp before it goes into the array. The document-level updatedAt is not
 * inside an array and keeps its sentinel.
 *
 * Firestore rejects undefined as well. In a patch it means "leave the field as
 * it is" — the ledger write reads it the same way — so those keys are dropped
 * rather than copied over the element; clearing a field takes an explicit null.
 */
function arraySafePatch(patch: Partial<PhotoRecord>): Partial<PhotoRecord> {
  return Object.fromEntries(
    Object.entries(patch)
      .filter(([, value]) => value !== undefined)
      .map(([key, value]) => [
        key,
        value instanceof FieldValue ? Timestamp.now() : value,
      ]),
  ) as Partial<PhotoRecord>;
}

/**
 * The photos array a moderation decision produces. Exported so a test can run
 * the real shape through Firestore's own write validator.
 */
export function buildModeratedPhotos(
  existing: PhotoRecord[],
  imageId: string,
  patch: Partial<PhotoRecord>,
): PhotoRecord[] {
  const index = existing.findIndex((photo) => String(photo.id ?? "") === imageId);
  const base: PhotoRecord = index >= 0
    ? existing[index]
    : {id: imageId, order: existing.length, isPrimary: existing.length === 0};
  const nextPhoto: PhotoRecord = {...base, ...arraySafePatch(patch)};
  return index >= 0
    ? existing.map((photo, photoIndex) => (photoIndex === index ? nextPhoto : photo))
    : [...existing, nextPhoto];
}

/**
 * The photos array a user report produces: every photo that is not already
 * rejected escalates to manual_review. Exported for the same reason.
 */
export function buildReportFlaggedPhotos(
  existing: PhotoRecord[],
  reason: string,
): PhotoRecord[] {
  return existing.map((photo) => {
    if (String(photo.moderationStatus ?? "pending") === "rejected") {
      return photo;
    }
    return {
      ...photo,
      moderationStatus: "manual_review",
      moderationReason: reason,
      moderatedAt: Timestamp.now(),
      moderatedBy: "report-pipeline",
    };
  });
}

export async function isSmokeTestAccount(db: Firestore, uid: string): Promise<boolean> {
  const snap = await db.doc(`users/${uid}`).get();
  return snap.data()?.isSmokeTestUser === true;
}

export async function setPhotoModerationStatus(
  db: Firestore,
  uid: string,
  imageId: string,
  patch: Partial<PhotoRecord>,
): Promise<void> {
  // The ledger is the authority; profiles.photos is the client-readable
  // projection of it. Record the decision first so a crash between the two
  // writes leaves the server stricter than the profile, never looser.
  if (patch.moderationStatus) {
    await writeLedgerEntry(db, uid, imageId, {
      status: patch.moderationStatus as PhotoModerationStatus,
      reason: (patch.moderationReason ?? null) as string | null,
      moderatedBy: (patch.moderatedBy ?? "system") as string,
      moderatedAt: patch.moderatedAt,
      storagePath: patch.storagePath,
      downloadUrl: patch.downloadUrl,
      thumbUrl: patch.thumbUrl,
      cardUrl: patch.cardUrl,
    });
  }
  const profileRef = db.doc(`profiles/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(profileRef);
    const photos = buildModeratedPhotos(photosFrom(snap.data()), imageId, patch);
    tx.set(profileRef, {photos, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
}

export interface PublishedPhoto {
  destPath: string;
  downloadUrl: string;
  /** Null when the variant could not be rendered; clients fall back to downloadUrl. */
  thumbUrl: string | null;
  cardUrl: string | null;
}

/**
 * Publishes an approved photo: the original is copied byte-for-byte to the
 * server-only photos/ prefix, and the display variants are rendered from the
 * same approved bytes. [sourceBuffer] is the buffer moderation already
 * downloaded; without it the pending object is read once more.
 */
export async function publishApprovedPhoto(options: {
  db: Firestore;
  bucket: Bucket;
  uid: string;
  imageId: string;
  sourcePath: string;
  contentType: string | undefined;
  sourceBuffer?: Buffer;
}): Promise<PublishedPhoto> {
  const extension = extensionForContentType(options.contentType);
  const destPath = `users/${options.uid}/profile/photos/${options.imageId}.${extension}`;
  const source = options.bucket.file(options.sourcePath);
  const dest = options.bucket.file(destPath);
  await source.copy(dest);
  const token = randomUUID();
  await dest.setMetadata({
    contentType: options.contentType ?? `image/${extension === "jpg" ? "jpeg" : extension}`,
    cacheControl: PHOTO_CACHE_CONTROL,
    metadata: {firebaseStorageDownloadTokens: token},
  });
  const downloadUrl = firebaseDownloadUrl(options.bucket.name, destPath, token);

  let sourceBuffer = options.sourceBuffer;
  if (!sourceBuffer) {
    try {
      [sourceBuffer] = await source.download({validation: false});
    } catch (error) {
      logger.warn("Approved photo source unreadable; publishing without variants", {
        uid: options.uid,
        imageId: options.imageId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  const variants = sourceBuffer
    ? await publishPhotoVariants({
      bucket: options.bucket,
      uid: options.uid,
      imageId: options.imageId,
      source: sourceBuffer,
    })
    : {};
  return {
    destPath,
    downloadUrl,
    thumbUrl: variants.thumb?.url ?? null,
    cardUrl: variants.card?.url ?? null,
  };
}

export async function processPendingProfilePhoto(options: {
  db: Firestore;
  bucket: Bucket;
  uid: string;
  imageId: string;
  pendingPath: string;
  contentType: string | undefined;
  sizeBytes: number;
}): Promise<PhotoModerationStatus> {
  // An imageId is moderated once. Storage rules let the owner write
  // pending/{imageId} again at any time; running the pipeline on that would
  // republish different bytes under an id the server has already ruled on —
  // an approved (or Face Anchor verified) photo swapped for another image, or
  // a moderator's removal undone by re-uploading. The new bytes are dropped.
  //
  // A photo whose object was published but whose status write never landed is
  // not "decided": it is still pending/processing here and the retry proceeds.
  const ledgerSnap = await ledgerRef(options.db, options.uid, options.imageId).get();
  if (ledgerSnap.exists) {
    const entry = ledgerEntryFromData(ledgerSnap.data() ?? {});
    const published = isPublishedStoragePath(options.uid, entry.storagePath);
    const decided =
      entry.status === "approved" ||
      (published && (entry.status === "manual_review" || entry.status === "rejected"));
    if (decided) {
      try {
        await options.bucket.file(options.pendingPath).delete({ignoreNotFound: true});
      } catch (error) {
        logger.warn("Failed to delete re-uploaded pending photo", {error: String(error)});
      }
      logger.warn("Ignored re-upload of an already moderated photo id", {
        uid: options.uid,
        imageId: options.imageId,
        status: entry.status,
      });
      return entry.status;
    }
  }

  const smokeFastPath = await isSmokeTestAccount(options.db, options.uid);
  const attemptsSnap = await options.db.doc(`profiles/${options.uid}`).get();
  const existing = photosFrom(attemptsSnap.data());
  const current = existing.find((photo) => photo.id === options.imageId);
  const attempts = Number(current?.processingAttempts ?? 0) + 1;

  await setPhotoModerationStatus(options.db, options.uid, options.imageId, {
    moderationStatus: "processing",
    processingAttempts: attempts,
    lastProcessingAttempt: FieldValue.serverTimestamp(),
    processingError: null,
  });

  try {
    const [buffer] = await options.bucket.file(options.pendingPath).download({validation: false});
    const result = await moderatePhotoBuffer({
      contentType: options.contentType,
      sizeBytes: options.sizeBytes,
      buffer,
      smokeFastPath,
    });

    if (result.status === "approved") {
      const published = await publishApprovedPhoto({
        db: options.db,
        bucket: options.bucket,
        uid: options.uid,
        imageId: options.imageId,
        sourcePath: options.pendingPath,
        contentType: options.contentType,
        sourceBuffer: buffer,
      });
      await setPhotoModerationStatus(options.db, options.uid, options.imageId, {
        storagePath: published.destPath,
        downloadUrl: published.downloadUrl,
        thumbUrl: published.thumbUrl,
        cardUrl: published.cardUrl,
        moderationStatus: "approved",
        moderationReason: result.reason ?? null,
        moderatedAt: FieldValue.serverTimestamp(),
        moderatedBy: "system",
        processingError: null,
      });
      logger.info("Photo approved by moderation pipeline", {
        uid: options.uid,
        imageId: options.imageId,
      });
      return "approved";
    }

    if (result.status === "rejected") {
      await setPhotoModerationStatus(options.db, options.uid, options.imageId, {
        moderationStatus: "rejected",
        moderationReason: result.reason ?? null,
        moderatedAt: FieldValue.serverTimestamp(),
        moderatedBy: "system",
        processingError: result.reason ?? null,
      });
      try {
        await options.bucket.file(options.pendingPath).delete({ignoreNotFound: true});
      } catch (error) {
        logger.warn("Failed to delete rejected pending photo", {error});
      }
      return "rejected";
    }

    await setPhotoModerationStatus(options.db, options.uid, options.imageId, {
      moderationStatus: "manual_review",
      moderationReason: result.reason ?? null,
      moderatedAt: FieldValue.serverTimestamp(),
      moderatedBy: "system",
      processingError: null,
    });
    return "manual_review";
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const nextStatus: PhotoModerationStatus =
      attempts >= MAX_PROCESSING_ATTEMPTS ? "manual_review" : "pending";
    await setPhotoModerationStatus(options.db, options.uid, options.imageId, {
      moderationStatus: nextStatus,
      processingAttempts: attempts,
      lastProcessingAttempt: FieldValue.serverTimestamp(),
      processingError: message,
      moderationReason: nextStatus === "manual_review" ? "processing-retries-exhausted" : null,
    });
    logger.error("Photo moderation processing failed", {
      uid: options.uid,
      imageId: options.imageId,
      attempts,
      error: message,
    });
    return nextStatus;
  }
}

export async function markProfilePhotosForManualReview(
  db: Firestore,
  reportedUserId: string,
  reason: string,
): Promise<void> {
  const profileRef = db.doc(`profiles/${reportedUserId}`);
  // Mirror the escalation into the ledger first so reconciliation agrees.
  const currentSnap = await profileRef.get();
  if (currentSnap.exists) {
    for (const photo of photosFrom(currentSnap.data())) {
      const imageId = String(photo.id ?? "");
      if (!imageId || String(photo.moderationStatus ?? "pending") === "rejected") {
        continue;
      }
      await writeLedgerEntry(db, reportedUserId, imageId, {
        status: "manual_review",
        reason,
        moderatedBy: "report-pipeline",
      });
    }
  }
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(profileRef);
    if (!snap.exists) {
      return;
    }
    const photos = buildReportFlaggedPhotos(photosFrom(snap.data()), reason);
    tx.set(
      profileRef,
      {
        photos,
        profileModerationStatus: "manual_review",
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });
}

export async function retryStaleProcessingPhotos(db: Firestore, bucket: Bucket): Promise<number> {
  const cutoff = new Date(Date.now() - PROCESSING_STALE_MS);
  const snap = await db.collection("profiles").limit(200).get();
  let retried = 0;
  for (const doc of snap.docs) {
    const photos = photosFrom(doc.data());
    for (const photo of photos) {
      if (photo.moderationStatus !== "processing" && photo.moderationStatus !== "pending") {
        continue;
      }
      const pendingPath = String(photo.storagePath ?? "");
      if (!pendingPath.includes("/profile/pending/")) {
        continue;
      }
      const lastAttempt = photo.lastProcessingAttempt;
      if (photo.moderationStatus === "processing") {
        const lastMs = lastAttempt && typeof lastAttempt === "object" && "toDate" in lastAttempt
          ? (lastAttempt as {toDate: () => Date}).toDate().getTime()
          : 0;
        if (lastMs > cutoff.getTime()) {
          continue;
        }
      }
      const file = bucket.file(pendingPath);
      const [exists] = await file.exists();
      if (!exists) {
        continue;
      }
      const [metadata] = await file.getMetadata();
      await processPendingProfilePhoto({
        db,
        bucket,
        uid: doc.id,
        imageId: String(photo.id),
        pendingPath,
        contentType: metadata.contentType,
        sizeBytes: Number(metadata.size ?? 0),
      });
      retried += 1;
    }
  }
  return retried;
}

/** The profile and ledger as one transaction saw them. */
export interface PhotoState {
  exists: boolean;
  profile: Record<string, unknown>;
  photos: PhotoRecord[];
  ledger: Map<string, LedgerEntry>;
}

/**
 * Reads everything the photo invariants depend on. Firestore transactions
 * read before they write, so a caller with reads of its own does those, then
 * this, and only then commitPhotoInvariants.
 */
export async function loadPhotoState(tx: Transaction, db: Firestore, uid: string): Promise<PhotoState> {
  const [profileSnap, ledgerSnap] = await Promise.all([
    tx.get(db.doc(`profiles/${uid}`)),
    tx.get(ledgerCollection(db, uid)),
  ]);
  const ledger = new Map<string, LedgerEntry>();
  for (const doc of ledgerSnap.docs) {
    ledger.set(doc.id, ledgerEntryFromData(doc.data() ?? {}));
  }
  const profile = (profileSnap.data() ?? {}) as Record<string, unknown>;
  return {exists: profileSnap.exists, profile, photos: photosFrom(profile), ledger};
}

export interface CommittedPhotoInvariants {
  changed: boolean;
  photos: PhotoRecord[];
  faceAnchorPhotoIds: string[];
}

/**
 * Queues the writes that bring profiles/{uid}.photos, faceAnchorPhotoIds and
 * the ledger back in line (photoInvariants.ts).
 *
 * `profilePatch` rides along on the same profile write. Nothing is written
 * when nothing would change, which is what keeps the profile trigger from
 * looping; an absent profile is never created.
 */
export function commitPhotoInvariants(
  tx: Transaction,
  db: Firestore,
  uid: string,
  state: PhotoState,
  options: {profilePatch?: Record<string, unknown>} = {},
): CommittedPhotoInvariants {
  if (!state.exists) {
    return {changed: false, photos: [], faceAnchorPhotoIds: []};
  }
  const result = computePhotoInvariants(state.photos, state.ledger);
  const photosDiffer = photosChanged(state.photos, result.photos);
  const anchorsDiffer = !sameIds(storedFaceAnchorPhotoIds(state.profile), result.faceAnchorPhotoIds);
  const patch = options.profilePatch ?? {};
  if (photosDiffer || anchorsDiffer || Object.keys(patch).length > 0) {
    tx.update(db.doc(`profiles/${uid}`), {
      ...(photosDiffer ? {photos: result.photos} : {}),
      ...(anchorsDiffer ? {faceAnchorPhotoIds: result.faceAnchorPhotoIds} : {}),
      ...patch,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const imageId of result.staleAnchorIds) {
    tx.update(ledgerRef(db, uid, imageId), {
      faceAnchor: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  return {
    changed: photosDiffer || anchorsDiffer || result.staleAnchorIds.length > 0,
    photos: result.photos,
    faceAnchorPhotoIds: result.faceAnchorPhotoIds,
  };
}

/**
 * Forces profiles/{uid}.photos to match the server-owned moderation ledger.
 *
 * Replaces the previous before/after heuristic, which decided whether a status
 * change was legitimate by reading photo.moderatedBy — a field the client
 * writes. Setting moderatedBy: "system" was enough to keep an unmoderated photo
 * marked approved, and a photo with no moderationStatus at all slipped past the
 * comparison entirely while approvedPhotos() treated it as approved.
 *
 * Authority now comes from users/{uid}/photoModeration/{imageId}, which is
 * denied to clients by the Firestore rules. Anything not recorded there is
 * unmoderated by definition and is forced back to "pending".
 *
 * Reads the profile itself, inside a transaction, rather than trusting the
 * array a trigger event carried: events arrive late and out of order, and an
 * old array written back would undo a newer write — or, with the Face Anchor
 * rules, drop a verdict over a photo that was never removed.
 *
 * Idempotent: a second pass over reconciled photos produces no write, so the
 * onDocumentWritten trigger does not loop.
 */
export async function reconcilePhotoModeration(
  db: Firestore,
  uid: string,
  bucket?: Bucket,
): Promise<boolean> {
  // Photos published by the pipeline before the ledger existed live under the
  // server-only photos/ prefix; adopt those rather than de-platforming. The
  // adoption checks Storage, so it cannot run inside the transaction: the
  // first pass only finds the candidates and writes nothing while there are any.
  const first = await db.runTransaction(async (tx) => {
    const state = await loadPhotoState(tx, db, uid);
    const candidates = computePhotoInvariants(state.photos, state.ledger).unrecordedPhotos
      .filter((photo) => isPublishedStoragePath(uid, photo.storagePath));
    if (state.exists && candidates.length > 0) {
      return {deferred: true as const, candidates};
    }
    return {deferred: false as const, changed: commitPhotoInvariants(tx, db, uid, state).changed};
  });
  if (!first.deferred) {
    return first.changed;
  }
  for (const photo of first.candidates) {
    await backfillLegacyApproval({db, bucket, uid, photo});
  }
  return db.runTransaction(async (tx) => {
    const state = await loadPhotoState(tx, db, uid);
    return commitPhotoInvariants(tx, db, uid, state).changed;
  });
}
