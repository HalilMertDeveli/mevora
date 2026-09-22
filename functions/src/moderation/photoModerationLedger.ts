import {FieldValue, type Firestore} from "firebase-admin/firestore";
import type {Bucket} from "@google-cloud/storage";
import {logger} from "firebase-functions";
import type {PhotoModerationStatus, PhotoRecord} from "./types.js";

/**
 * Server-owned moderation ledger.
 *
 * profiles/{uid}.photos is a client-writable array — Firestore rules cannot
 * validate the fields of array elements, so the rule layer cannot stop a
 * modified client from writing moderationStatus: "approved" there.
 *
 * The ledger is the authority instead: users/{uid}/photoModeration/{imageId}
 * is written only through the Admin SDK and denied to clients by the rules.
 * enforceProfilePhotoModeration reconciles the profile array against it, so
 * whatever a client writes into photos[] is overwritten with the server's
 * decision on the next trigger pass.
 */

export const LEDGER_COLLECTION = "photoModeration";

/** Fields the client must never decide. Reconciliation always overwrites these. */
export const SERVER_OWNED_PHOTO_FIELDS = [
  "moderationStatus",
  "moderationReason",
  "moderatedAt",
  "moderatedBy",
  "processingAttempts",
  "lastProcessingAttempt",
  "processingError",
] as const;

/** Fields the client legitimately owns: presentation only. */
export const CLIENT_OWNED_PHOTO_FIELDS = ["id", "order", "isPrimary", "thumbUrl"] as const;

export interface LedgerEntry {
  status: PhotoModerationStatus;
  reason?: string | null;
  moderatedBy?: string | null;
  moderatedAt?: unknown;
  storagePath?: string | null;
  downloadUrl?: string | null;
}

export function ledgerRef(db: Firestore, uid: string, imageId: string) {
  return db.doc(`users/${uid}/${LEDGER_COLLECTION}/${imageId}`);
}

/** Records the server's moderation decision. Admin SDK only. */
export async function writeLedgerEntry(
  db: Firestore,
  uid: string,
  imageId: string,
  entry: LedgerEntry,
): Promise<void> {
  await ledgerRef(db, uid, imageId).set(
    {
      imageId,
      status: entry.status,
      reason: entry.reason ?? null,
      moderatedBy: entry.moderatedBy ?? "system",
      moderatedAt: entry.moderatedAt ?? FieldValue.serverTimestamp(),
      ...(entry.storagePath === undefined ? {} : {storagePath: entry.storagePath}),
      ...(entry.downloadUrl === undefined ? {} : {downloadUrl: entry.downloadUrl}),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

export async function readLedger(
  db: Firestore,
  uid: string,
): Promise<Map<string, LedgerEntry>> {
  const snap = await db.collection(`users/${uid}/${LEDGER_COLLECTION}`).get();
  const out = new Map<string, LedgerEntry>();
  for (const doc of snap.docs) {
    const data = doc.data() ?? {};
    out.set(doc.id, {
      status: String(data.status ?? "pending") as PhotoModerationStatus,
      reason: (data.reason ?? null) as string | null,
      moderatedBy: (data.moderatedBy ?? null) as string | null,
      moderatedAt: data.moderatedAt,
      storagePath: (data.storagePath ?? null) as string | null,
      downloadUrl: (data.downloadUrl ?? null) as string | null,
    });
  }
  return out;
}

/**
 * Only the moderation pipeline can write under users/{uid}/profile/photos/ —
 * the Storage rules deny every client write to that prefix. A photo already
 * sitting there predates the ledger and was published by the pipeline, so it
 * can be grandfathered as approved once the object is confirmed to exist.
 */
export function isPublishedStoragePath(uid: string, storagePath: unknown): boolean {
  return (
    typeof storagePath === "string" &&
    storagePath.startsWith(`users/${uid}/profile/photos/`)
  );
}

export async function backfillLegacyApproval(options: {
  db: Firestore;
  bucket?: Bucket;
  uid: string;
  photo: PhotoRecord;
}): Promise<LedgerEntry | null> {
  const {db, bucket, uid, photo} = options;
  const imageId = String(photo.id ?? "");
  if (!imageId || !isPublishedStoragePath(uid, photo.storagePath)) {
    return null;
  }
  // Claiming the path is not enough; the object must actually be there.
  if (bucket) {
    try {
      const [exists] = await bucket.file(String(photo.storagePath)).exists();
      if (!exists) {
        return null;
      }
    } catch (error) {
      logger.warn("Legacy photo backfill could not verify storage object", {
        uid,
        imageId,
        error: String(error),
      });
      return null;
    }
  }
  const entry: LedgerEntry = {
    status: "approved",
    reason: null,
    moderatedBy: "legacy-backfill",
    storagePath: String(photo.storagePath),
    downloadUrl: (photo.downloadUrl ?? null) as string | null,
  };
  await writeLedgerEntry(db, uid, imageId, entry);
  logger.info("Backfilled ledger for pipeline-published legacy photo", {uid, imageId});
  return entry;
}

/**
 * Projects one profile photo onto the server's decision.
 *
 * No ledger entry means the photo has never been moderated, whatever the client
 * wrote — it is forced back to "pending" and its moderation metadata cleared.
 * An approved photo also takes its storagePath/downloadUrl from the ledger, so
 * a client cannot attach an arbitrary external URL to an approved entry.
 */
export function reconcilePhoto(photo: PhotoRecord, entry: LedgerEntry | null): PhotoRecord {
  const next: PhotoRecord = {...photo};
  if (!entry) {
    next.moderationStatus = "pending";
    next.moderationReason = null;
    next.moderatedAt = null;
    next.moderatedBy = null;
    return next;
  }
  next.moderationStatus = entry.status;
  next.moderationReason = entry.reason ?? null;
  next.moderatedBy = entry.moderatedBy ?? null;
  if (entry.moderatedAt !== undefined) {
    next.moderatedAt = entry.moderatedAt;
  }
  if (entry.status === "approved") {
    if (entry.storagePath) {
      next.storagePath = entry.storagePath;
    }
    if (entry.downloadUrl) {
      next.downloadUrl = entry.downloadUrl;
    }
  }
  return next;
}

function sameValue(a: unknown, b: unknown): boolean {
  if (a === b) {
    return true;
  }
  if (a == null && b == null) {
    return true;
  }
  const at = a as {toMillis?: () => number};
  const bt = b as {toMillis?: () => number};
  if (typeof at?.toMillis === "function" && typeof bt?.toMillis === "function") {
    return at.toMillis() === bt.toMillis();
  }
  return false;
}

/** True when reconciliation would change the photo — used to avoid trigger loops. */
export function photoChanged(before: PhotoRecord, after: PhotoRecord): boolean {
  const a = before as unknown as Record<string, unknown>;
  const b = after as unknown as Record<string, unknown>;
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const key of keys) {
    if (!sameValue(a[key], b[key])) {
      return true;
    }
  }
  return false;
}
