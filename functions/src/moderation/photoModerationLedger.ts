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
  // B-11: thumbUrl was treated as client presentation data, but discovery
  // renders `thumbUrl ?? downloadUrl`, so a client-supplied thumbnail URL was
  // preferred over the moderated one — a route around B-02 needing no Storage
  // write at all. The display variants are rendered by publishApprovedPhoto
  // from the approved bytes and recorded in the ledger; whatever a client
  // writes here is replaced with the ledger's value (or null).
  "thumbUrl",
  "cardUrl",
  // Whether this photo is a verified Face Anchor. Decided by the face
  // verification pipeline (faceAnchor/), recorded on the ledger entry.
  "faceAnchorVerified",
] as const;

/**
 * Fields the client proposes: identity and ordering. `order` and `isPrimary`
 * are honoured only as far as the Face Anchor invariants allow — once a
 * profile has a usable anchor the primary photo is one, whatever was written
 * (see photoInvariants.ts).
 */
export const CLIENT_OWNED_PHOTO_FIELDS = ["id", "order", "isPrimary"] as const;

/**
 * The server's record that this photo was matched to the live account owner.
 *
 * Deliberately small: no similarity score, no liveness result, no provider
 * payload or request id. `storagePath` pins the verdict to the published
 * object it was made about — an entry whose published path differs is not an
 * anchor.
 */
export interface FaceAnchorLedgerState {
  status: "verified";
  verifiedAt?: unknown;
  provider?: string | null;
  attemptId?: string | null;
  storagePath?: string | null;
}

export interface LedgerEntry {
  status: PhotoModerationStatus;
  reason?: string | null;
  moderatedBy?: string | null;
  moderatedAt?: unknown;
  storagePath?: string | null;
  downloadUrl?: string | null;
  /** B-11: server-owned. Rendered by publishApprovedPhoto (photoVariants.ts). */
  thumbUrl?: string | null;
  /** Server-owned card-size variant; same authority as thumbUrl. */
  cardUrl?: string | null;
  /** Read-only here: written by the face verification pipeline, never by moderation. */
  faceAnchor?: FaceAnchorLedgerState | null;
  /**
   * Read-only here: written by deleteProfilePhoto when the member removes a
   * photo whose entry moderation keeps (rejected or held for review). The
   * photo is off the profile for good; only the record and the reviewer's
   * copy of the image are left. See isRemovedByMember.
   */
  removedByMemberAt?: unknown;
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
      ...(entry.thumbUrl === undefined ? {} : {thumbUrl: entry.thumbUrl}),
      ...(entry.cardUrl === undefined ? {} : {cardUrl: entry.cardUrl}),
      // A rejected photo is no longer evidence of anything: the verdict goes
      // with it, so a later re-approval starts from an unverified photo.
      ...(entry.status === "rejected" ? {faceAnchor: FieldValue.delete()} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

function parseFaceAnchor(raw: unknown): FaceAnchorLedgerState | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  const data = raw as Record<string, unknown>;
  // Anything but the exact word is not a verdict.
  if (data.status !== "verified") {
    return null;
  }
  return {
    status: "verified",
    verifiedAt: data.verifiedAt,
    provider: typeof data.provider === "string" ? data.provider : null,
    attemptId: typeof data.attemptId === "string" ? data.attemptId : null,
    storagePath: typeof data.storagePath === "string" ? data.storagePath : null,
  };
}

export function ledgerEntryFromData(data: Record<string, unknown>): LedgerEntry {
  return {
    status: String(data.status ?? "pending") as PhotoModerationStatus,
    reason: (data.reason ?? null) as string | null,
    moderatedBy: (data.moderatedBy ?? null) as string | null,
    moderatedAt: data.moderatedAt,
    storagePath: (data.storagePath ?? null) as string | null,
    downloadUrl: (data.downloadUrl ?? null) as string | null,
    thumbUrl: (data.thumbUrl ?? null) as string | null,
    cardUrl: (data.cardUrl ?? null) as string | null,
    faceAnchor: parseFaceAnchor(data.faceAnchor),
    removedByMemberAt: data.removedByMemberAt ?? null,
  };
}

/**
 * True when the member removed this photo through the server while moderation
 * was keeping its record. Nothing may put such a photo back on the profile: a
 * later decision is recorded, never projected as a new array entry.
 *
 * The array alone cannot say this. An id missing from profiles/{uid}.photos is
 * also what a photo looks like between its upload and the client's array
 * write, and what a stale whole-array write leaves for a moment.
 */
export function isRemovedByMember(entry: LedgerEntry | null | undefined): boolean {
  return entry?.removedByMemberAt != null;
}

export function ledgerCollection(db: Firestore, uid: string) {
  return db.collection(`users/${uid}/${LEDGER_COLLECTION}`);
}

export async function readLedger(
  db: Firestore,
  uid: string,
): Promise<Map<string, LedgerEntry>> {
  const snap = await ledgerCollection(db, uid).get();
  const out = new Map<string, LedgerEntry>();
  for (const doc of snap.docs) {
    out.set(doc.id, ledgerEntryFromData(doc.data() ?? {}));
  }
  return out;
}

/**
 * True when the ledger says this photo is a Face Anchor right now: approved by
 * moderation, verified against the live owner, and still the same published
 * object the verdict was made about.
 *
 * A photo held in manual_review keeps its verdict but is not an anchor while
 * it is held; a rejected one loses the verdict (writeLedgerEntry).
 */
export function isLedgerFaceAnchor(entry: LedgerEntry | null | undefined): boolean {
  return (
    entry?.status === "approved" &&
    entry.faceAnchor?.status === "verified" &&
    typeof entry.storagePath === "string" &&
    entry.storagePath.length > 0 &&
    entry.faceAnchor.storagePath === entry.storagePath
  );
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
  // B-11: the variant URLs are server-owned. Only the ledger may supply them,
  // so a client cannot point discovery at unmoderated imagery through the
  // `thumbUrl ?? downloadUrl` fallback — and only while the photo is
  // approved, so a photo pulled back into review stops rendering anywhere.
  const approved = entry?.status === "approved";
  next.thumbUrl = approved ? entry?.thumbUrl ?? null : null;
  next.cardUrl = approved ? entry?.cardUrl ?? null : null;
  // Present only while true, so documents written before Face Anchor existed
  // reconcile to themselves. A client-written value never survives this.
  if (isLedgerFaceAnchor(entry)) {
    next.faceAnchorVerified = true;
  } else {
    delete next.faceAnchorVerified;
  }
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
