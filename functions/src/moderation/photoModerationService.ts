import {randomUUID} from "node:crypto";
import {FieldValue, type Firestore} from "firebase-admin/firestore";
import type {Bucket} from "@google-cloud/storage";
import {logger} from "firebase-functions";
import {moderatePhotoBuffer} from "./manualModerationProvider.js";
import {
  MAX_PROCESSING_ATTEMPTS,
  PROCESSING_STALE_MS,
  type PhotoModerationStatus,
  type PhotoRecord,
} from "./types.js";

function extensionForContentType(contentType: string | undefined): string {
  const lower = String(contentType ?? "").toLowerCase();
  if (lower.includes("png")) return "png";
  if (lower.includes("webp")) return "webp";
  return "jpg";
}

function photosFrom(data: Record<string, unknown> | undefined): PhotoRecord[] {
  return ((data?.photos as PhotoRecord[] | undefined) ?? []).map((photo) => ({...photo}));
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
  const profileRef = db.doc(`profiles/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(profileRef);
    const existing = photosFrom(snap.data());
    const index = existing.findIndex((photo) => String(photo.id ?? "") === imageId);
    const base: PhotoRecord = index >= 0
      ? existing[index]
      : {id: imageId, order: existing.length, isPrimary: existing.length === 0};
    const nextPhoto: PhotoRecord = {...base, ...patch};
    const photos = index >= 0
      ? existing.map((photo, photoIndex) => (photoIndex === index ? nextPhoto : photo))
      : [...existing, nextPhoto];
    tx.set(profileRef, {photos, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
}

async function publishApprovedPhoto(options: {
  db: Firestore;
  bucket: Bucket;
  uid: string;
  imageId: string;
  sourcePath: string;
  contentType: string | undefined;
}): Promise<{destPath: string; downloadUrl: string}> {
  const extension = extensionForContentType(options.contentType);
  const destPath = `users/${options.uid}/profile/photos/${options.imageId}.${extension}`;
  const source = options.bucket.file(options.sourcePath);
  const dest = options.bucket.file(destPath);
  await source.copy(dest);
  const token = randomUUID();
  await dest.setMetadata({
    contentType: options.contentType ?? `image/${extension === "jpg" ? "jpeg" : extension}`,
    metadata: {firebaseStorageDownloadTokens: token},
  });
  const downloadUrl =
    `https://firebasestorage.googleapis.com/v0/b/${options.bucket.name}/o/` +
    `${encodeURIComponent(destPath)}?alt=media&token=${token}`;
  return {destPath, downloadUrl};
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
      });
      await setPhotoModerationStatus(options.db, options.uid, options.imageId, {
        storagePath: published.destPath,
        downloadUrl: published.downloadUrl,
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
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(profileRef);
    if (!snap.exists) {
      return;
    }
    const photos = photosFrom(snap.data()).map((photo) => {
      if (String(photo.moderationStatus ?? "pending") === "rejected") {
        return photo;
      }
      return {
        ...photo,
        moderationStatus: "manual_review",
        moderationReason: reason,
        moderatedAt: FieldValue.serverTimestamp(),
        moderatedBy: "report-pipeline",
      };
    });
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

export async function stripClientModerationEscalations(
  db: Firestore,
  uid: string,
  beforePhotos: PhotoRecord[],
  afterPhotos: PhotoRecord[],
): Promise<boolean> {
  const beforeById = new Map(beforePhotos.map((photo) => [String(photo.id), photo]));
  let changed = false;
  const sanitized = afterPhotos.map((photo) => {
    const previous = beforeById.get(String(photo.id));
    const nextStatus = String(photo.moderationStatus ?? "pending");
    const prevStatus = String(previous?.moderationStatus ?? "pending");
    const moderatedBy = photo.moderatedBy;
    if (
      nextStatus !== prevStatus &&
      ["approved", "rejected", "manual_review"].includes(nextStatus) &&
      moderatedBy !== "system" &&
      moderatedBy !== "report-pipeline"
    ) {
      changed = true;
      return {
        ...photo,
        moderationStatus: prevStatus === "pending" ? "pending" : prevStatus,
        moderationReason: "client-escalation-blocked",
        moderatedBy: null,
        moderatedAt: null,
      };
    }
    return photo;
  });
  if (changed) {
    await db.doc(`profiles/${uid}`).set(
      {photos: sanitized, updatedAt: FieldValue.serverTimestamp()},
      {merge: true},
    );
  }
  return changed;
}
