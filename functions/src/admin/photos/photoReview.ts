import {createHash} from "node:crypto";
import {FieldValue, Timestamp, type Firestore, type Query} from "firebase-admin/firestore";
import type {Bucket} from "@google-cloud/storage";
import {
  isLedgerFaceAnchor,
  isPublishedStoragePath,
  ledgerEntryFromData,
  ledgerRef,
  readLedger,
} from "../../moderation/photoModerationLedger.js";
import {publishApprovedPhoto, setPhotoModerationStatus} from "../../moderation/photoModerationService.js";
import {deletePhotoVariants} from "../../moderation/photoVariants.js";
import {ACTION_COLLECTION, buildActionRecord, type ActionType} from "../actions/actionTypes.js";
import {appendAuditEvent, recordAuditEvent} from "../audit/auditService.js";
import type {AdminActor} from "../auth/adminAuthorization.js";
import {linkActionToCase, openOrAttachCase, readLinkableCase} from "../cases/caseService.js";
import type {AdminBucketPort, AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, deterministicId, encodeCursor, iso, toMillis} from "../validation.js";
import {loadUserCards} from "../users/userCards.js";

/**
 * Admin photo review on top of the existing moderation pipeline.
 *
 * Authority stays exactly where it was: `users/{uid}/photoModeration/{imageId}`
 * (the server-owned ledger). An admin decision is written through
 * setPhotoModerationStatus — the same function the automated pipeline uses —
 * which records the ledger first and then projects it onto profiles/{uid}.photos;
 * enforceProfilePhotoModeration keeps reconciling that array against the
 * ledger afterwards. The admin console never writes the photos array itself.
 *
 * Approving an unpublished photo publishes it with the pipeline's own
 * publishApprovedPhoto (server-only photos/ prefix). Rejecting moves the
 * object into a server-only quarantine prefix (kept for the appeal window,
 * then removed by retention) instead of leaving it readable.
 */

export const PHOTO_QUEUE_FILTERS = ["manual_review", "pending_too_long", "retries_exhausted", "reported"] as const;
export type PhotoQueueFilter = (typeof PHOTO_QUEUE_FILTERS)[number];

export const PENDING_TOO_LONG_MS = 30 * 60 * 1000;
export const QUARANTINE_PREFIX = "moderation/quarantine";
export const MAX_PREVIEW_BYTES = 5 * 1024 * 1024;
const REVIEW_LOCK_MS = 2 * 60 * 1000;
const EXTENSION = /\.(jpg|jpeg|png|webp)$/i;

/** Ledger status the admin console may act on, per decision. */
const REVIEWABLE = new Set(["manual_review", "pending", "processing"]);

/**
 * The ledger is owner-readable, so the review lock must not name the
 * moderator: it stores an opaque token derived from their uid.
 */
export function reviewerToken(uid: string): string {
  return createHash("sha256").update(`photo-review:${uid}`).digest("hex").slice(0, 16);
}

function uidFromLedgerPath(path: string): string {
  // users/{uid}/photoModeration/{imageId}
  return path.split("/")[1] ?? "";
}

export async function listPhotoReviews(
  deps: AdminDeps,
  input: {filter: PhotoQueueFilter; cursor: unknown; limit: number},
  actorUid = "",
) {
  const {db} = deps;
  const nowMs = deps.now();
  let q: Query = db.collectionGroup("photoModeration");
  switch (input.filter) {
  case "manual_review":
    q = q.where("status", "==", "manual_review");
    break;
  case "retries_exhausted":
    q = q.where("status", "==", "manual_review").where("reason", "==", "processing-retries-exhausted");
    break;
  case "reported":
    q = q.where("status", "==", "manual_review").where("moderatedBy", "==", "report-pipeline");
    break;
  case "pending_too_long":
    q = q.where("status", "in", ["pending", "processing"])
      .where("updatedAt", "<=", Timestamp.fromMillis(nowMs - PENDING_TOO_LONG_MS));
    break;
  }
  q = q.orderBy("updatedAt", "asc").orderBy("__name__", "asc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const uids = [...new Set(snap.docs.map((doc) => uidFromLedgerPath(doc.ref.path)))];
  const [cards, profiles, openReports] = await Promise.all([
    loadUserCards(db, uids, nowMs),
    uids.length ? db.getAll(...uids.map((u) => db.doc(`profiles/${u}`))) : Promise.resolve([]),
    Promise.all(uids.map(async (u) => {
      try {
        const c = await db.collection("reports").where("reportedUserId", "==", u).where("status", "==", "open").count().get();
        return [u, c.data().count] as const;
      } catch {
        return [u, null] as const;
      }
    })),
  ]);
  const profileByUid = new Map(profiles.map((p) => [p.id, p.data() ?? {}]));
  const reportsByUid = new Map(openReports);
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: snap.docs.map((doc) => {
      const uid = uidFromLedgerPath(doc.ref.path);
      const data = doc.data();
      const photo = ((profileByUid.get(uid)?.photos as Array<Record<string, unknown>> | undefined) ?? [])
        .find((p) => String(p.id ?? "") === doc.id);
      return {
        uid,
        imageId: doc.id,
        status: data.status ?? "pending",
        reason: data.reason ?? null,
        moderatedBy: data.moderatedBy ?? null,
        updatedAt: iso(data.updatedAt),
        moderatedAt: iso(data.moderatedAt),
        published: isPublishedStoragePath(uid, data.storagePath),
        processingAttempts: typeof photo?.processingAttempts === "number" ? photo.processingAttempts : null,
        lastProcessingAttempt: iso(photo?.lastProcessingAttempt),
        processingError: typeof photo?.processingError === "string" ? photo.processingError.slice(0, 200) : null,
        isPrimary: photo?.isPrimary === true,
        // So a reviewer can see that removing this photo takes away the
        // member's verified anchor. The verdict only — nothing about how it
        // was reached is stored to show.
        faceAnchor: isLedgerFaceAnchor(ledgerEntryFromData(data)) ? "verified" : "none",
        user: cards.get(uid) ?? null,
        openReportCount: reportsByUid.get(uid) ?? null,
        lock: data.reviewLock && toMillis(data.reviewLock.at) !== null &&
          (toMillis(data.reviewLock.at) as number) > nowMs - REVIEW_LOCK_MS
          ? (data.reviewLock.token === reviewerToken(actorUid) ? "you" : "another_reviewer")
          : null,
      };
    }),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("updatedAt")), last.ref.path])
      : null,
  };
}

async function findPendingObject(bucket: AdminBucketPort, uid: string, imageId: string): Promise<string | null> {
  const prefix = `users/${uid}/profile/pending/${imageId}`;
  const [files] = await bucket.getFiles({prefix, maxResults: 10, autoPaginate: false});
  const match = files.find((f) => f.name === prefix || (f.name.startsWith(`${prefix}.`) && EXTENSION.test(f.name)));
  return match?.name ?? null;
}

async function findQuarantineObject(bucket: AdminBucketPort, uid: string, imageId: string): Promise<string | null> {
  const prefix = `${QUARANTINE_PREFIX}/${uid}/${imageId}`;
  const [files] = await bucket.getFiles({prefix, maxResults: 5, autoPaginate: false});
  return files.find((f) => f.name === prefix || f.name.startsWith(`${prefix}.`))?.name ?? null;
}

/** Where the image bytes for this photo live right now, if anywhere. */
async function locatePhotoObject(
  deps: AdminDeps,
  uid: string,
  imageId: string,
  ledgerStoragePath: unknown,
): Promise<{path: string; source: "published" | "pending" | "quarantine"} | null> {
  const bucket = deps.bucket();
  if (isPublishedStoragePath(uid, ledgerStoragePath)) {
    const [exists] = await bucket.file(String(ledgerStoragePath)).exists();
    if (exists) {
      return {path: String(ledgerStoragePath), source: "published"};
    }
  }
  const pending = await findPendingObject(bucket, uid, imageId);
  if (pending) {
    return {path: pending, source: "pending"};
  }
  const quarantined = await findQuarantineObject(bucket, uid, imageId);
  if (quarantined) {
    return {path: quarantined, source: "quarantine"};
  }
  return null;
}

/**
 * Image bytes for the reviewer, fetched server-side. No signed URL is minted
 * and the bucket stays private: the admin web streams these bytes to the
 * reviewer's browser with no-store caching.
 */
export async function getPhotoPreview(deps: AdminDeps, input: {uid: string; imageId: string}) {
  const ledgerSnap = await ledgerRef(deps.db, input.uid, input.imageId).get();
  const located = await locatePhotoObject(deps, input.uid, input.imageId, ledgerSnap.get("storagePath"));
  if (!located) {
    throw new AdminError("not_found", "photo_object");
  }
  const file = deps.bucket().file(located.path);
  const [metadata] = await file.getMetadata();
  const size = Number(metadata.size ?? 0);
  if (size > MAX_PREVIEW_BYTES) {
    throw new AdminError("invalid_state_transition", "photo_too_large");
  }
  const contentType = String(metadata.contentType ?? "");
  if (!/^image\/(jpeg|jpg|png|webp)$/i.test(contentType)) {
    throw new AdminError("invalid_state_transition", "unsupported_content_type");
  }
  const [buffer] = await file.download({validation: false});
  return {
    uid: input.uid,
    imageId: input.imageId,
    source: located.source,
    contentType,
    dataBase64: buffer.toString("base64"),
  };
}

async function quarantine(deps: AdminDeps, uid: string, imageId: string, sourcePath: string): Promise<string> {
  const bucket = deps.bucket();
  const extension = (sourcePath.match(EXTENSION)?.[1] ?? "jpg").toLowerCase();
  const destination = `${QUARANTINE_PREFIX}/${uid}/${imageId}.${extension}`;
  await bucket.file(sourcePath).copy(bucket.file(destination));
  await bucket.file(sourcePath).delete({ignoreNotFound: true});
  return destination;
}

/** Profile visibility follows its photos: no photo left in review → approved. */
async function settleProfileModerationStatus(db: Firestore, uid: string): Promise<void> {
  const ledger = await readLedger(db, uid);
  const stillReviewing = [...ledger.values()].some((entry) =>
    entry.status === "manual_review" || entry.status === "processing");
  if (stillReviewing) {
    return;
  }
  const profileRef = db.doc(`profiles/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(profileRef);
    if (snap.exists && snap.get("profileModerationStatus") === "manual_review") {
      tx.set(profileRef, {profileModerationStatus: "approved", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
  });
}

export interface PhotoDecisionInput {
  uid: string;
  imageId: string;
  decision: "approve" | "reject" | "escalate";
  reasonCode: string | null;
  internalNote: string | null;
  caseId: string | null;
  idempotencyKey: string;
}

export async function reviewPhoto(
  deps: AdminDeps,
  actor: AdminActor,
  input: PhotoDecisionInput,
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const ref = ledgerRef(db, input.uid, input.imageId);

  if (input.decision === "escalate") {
    const snap = await ref.get();
    if (!snap.exists) {
      throw new AdminError("not_found", "photo");
    }
    const result = await openOrAttachCase(db, {
      type: "PHOTO_REVIEW",
      correlationKey: `photo:${input.uid}`,
      subjectUserId: input.uid,
      sourceRef: ref.path,
      reasonCode: input.reasonCode,
      priority: "high",
      summary: "Photo escalated for senior review",
      createdBy: actor.uid,
      createdByRole: actor.role,
      requestId,
    }, nowMs);
    await recordAuditEvent(db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "PHOTO_ESCALATED",
      targetType: "photo",
      targetId: ref.path,
      caseId: result.caseId,
      requestId,
      metadata: {reasonCode: input.reasonCode, internalNote: input.internalNote ?? ""},
    }, nowMs);
    return {decision: "escalate", caseId: result.caseId, replayed: false, status: snap.get("status") ?? null};
  }

  if (input.decision === "reject" && !input.reasonCode) {
    throw new AdminError("invalid_argument", "reasonCode");
  }
  const actionId = deterministicId("act", actor.uid, "photo", input.uid, input.imageId, input.idempotencyKey);
  const actionRef = db.doc(`${ACTION_COLLECTION}/${actionId}`);

  // 1. Claim the photo (or replay). Two reviewers cannot decide it at once.
  const claim = await db.runTransaction(async (tx) => {
    const [actionSnap, ledgerSnap, profileSnap] = await Promise.all([
      tx.get(actionRef),
      tx.get(ref),
      tx.get(db.doc(`profiles/${input.uid}`)),
    ]);
    if (actionSnap.exists) {
      return {replay: true as const, action: actionSnap.data() ?? {}};
    }
    const inProfile = ((profileSnap.get("photos") as Array<Record<string, unknown>> | undefined) ?? [])
      .some((p) => String(p.id ?? "") === input.imageId);
    if (!ledgerSnap.exists && !inProfile) {
      throw new AdminError("not_found", "photo");
    }
    const status = String(ledgerSnap.get("status") ?? "pending");
    const lock = ledgerSnap.get("reviewLock") as {token?: string; at?: unknown} | undefined;
    const lockAt = toMillis(lock?.at);
    const mine = reviewerToken(actor.uid);
    if (lock?.token && lock.token !== mine && lockAt !== null && lockAt > nowMs - REVIEW_LOCK_MS) {
      throw new AdminError("photo_review_in_progress");
    }
    const approvable = REVIEWABLE.has(status);
    const rejectable = REVIEWABLE.has(status) || status === "approved";
    if ((input.decision === "approve" && !approvable) || (input.decision === "reject" && !rejectable)) {
      throw new AdminError("photo_already_reviewed", "photo_already_reviewed", {status});
    }
    tx.set(ref, {imageId: input.imageId, reviewLock: {token: mine, at: Timestamp.fromMillis(nowMs)}}, {merge: true});
    return {
      replay: false as const,
      status,
      storagePath: ledgerSnap.get("storagePath") as string | undefined,
      downloadUrl: ledgerSnap.get("downloadUrl") as string | undefined,
    };
  });

  if (claim.replay) {
    return {
      decision: input.decision,
      actionId,
      replayed: true,
      status: String((claim.action.newState as Record<string, unknown> | undefined)?.status ?? ""),
    };
  }

  const releaseLock = () => ref.set({reviewLock: FieldValue.delete()}, {merge: true});
  let actionType: ActionType;
  let newStatus: "approved" | "rejected";
  let quarantinedTo: string | null = null;
  try {
    if (input.decision === "approve") {
      actionType = "PHOTO_APPROVED";
      newStatus = "approved";
      let storagePath = isPublishedStoragePath(input.uid, claim.storagePath) ? claim.storagePath : undefined;
      let downloadUrl = storagePath ? claim.downloadUrl : undefined;
      // Left undefined when the photo is already published (e.g. a reported
      // photo re-approved): the ledger keeps the variants it already has.
      let thumbUrl: string | null | undefined;
      let cardUrl: string | null | undefined;
      if (!storagePath || !downloadUrl) {
        const bucket = deps.bucket();
        const pending = await findPendingObject(bucket, input.uid, input.imageId);
        if (!pending) {
          throw new AdminError("invalid_state_transition", "pending_object_missing");
        }
        const [metadata] = await bucket.file(pending).getMetadata();
        const published = await publishApprovedPhoto({
          db,
          bucket: bucket as unknown as Bucket,
          uid: input.uid,
          imageId: input.imageId,
          sourcePath: pending,
          contentType: metadata.contentType,
        });
        storagePath = published.destPath;
        downloadUrl = published.downloadUrl;
        thumbUrl = published.thumbUrl;
        cardUrl = published.cardUrl;
      }
      await setPhotoModerationStatus(db, input.uid, input.imageId, {
        moderationStatus: "approved",
        moderationReason: "admin-approved",
        moderatedBy: "admin_review",
        moderatedAt: FieldValue.serverTimestamp(),
        storagePath,
        downloadUrl,
        thumbUrl,
        cardUrl,
        processingError: null,
      });
    } else {
      const wasPublished = claim.status === "approved" || isPublishedStoragePath(input.uid, claim.storagePath);
      actionType = wasPublished ? "PHOTO_REMOVED" : "PHOTO_REJECTED";
      newStatus = "rejected";
      const located = await locatePhotoObject(deps, input.uid, input.imageId, claim.storagePath);
      if (located && located.source !== "quarantine") {
        quarantinedTo = await quarantine(deps, input.uid, input.imageId, located.path);
      }
      // The display variants are copies of the same image; the quarantined
      // original is the evidence, so they are simply removed.
      await deletePhotoVariants(deps.bucket(), input.uid, input.imageId);
      await setPhotoModerationStatus(db, input.uid, input.imageId, {
        moderationStatus: "rejected",
        moderationReason: input.reasonCode,
        moderatedBy: "admin_review",
        moderatedAt: FieldValue.serverTimestamp(),
        // The published copy is gone; nothing may keep pointing at it.
        downloadUrl: null,
        thumbUrl: null,
        cardUrl: null,
      });
    }
  } catch (error) {
    await releaseLock();
    throw error;
  }

  // 2. Record the decision alongside its audit trail and case link.
  await db.runTransaction(async (tx) => {
    const linkedCase = await readLinkableCase(tx, db, input.caseId);
    tx.create(actionRef, {
      ...buildActionRecord({
        actionId,
        type: actionType,
        targetUserId: input.uid,
        caseId: input.caseId,
        reasonCode: input.reasonCode ?? "APPROVED",
        internalNote: input.internalNote,
        actorAdminId: actor.uid,
        actorRole: actor.role,
        requestId,
        idempotencyKey: input.idempotencyKey,
        effectiveAtMs: nowMs,
        previousState: {status: claim.status},
        newState: {status: newStatus},
        subject: {imageId: input.imageId, ledgerPath: ref.path, quarantinePath: quarantinedTo},
      }),
    });
    tx.set(ref, {reviewLock: FieldValue.delete(), decisionActionId: actionId}, {merge: true});
    if (linkedCase) {
      linkActionToCase(tx, db, linkedCase, {actionId, actionType, actor}, nowMs);
    }
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: actionType === "PHOTO_APPROVED" ? "PHOTO_APPROVED" : actionType === "PHOTO_REMOVED" ? "PHOTO_REMOVED" : "PHOTO_REJECTED",
      targetType: "photo",
      targetId: ref.path,
      caseId: input.caseId,
      actionId,
      requestId,
      metadata: {
        userId: input.uid,
        imageId: input.imageId,
        previousStatus: claim.status,
        reasonCode: input.reasonCode,
        internalNote: input.internalNote ?? "",
      },
    }, nowMs);
  });

  await settleProfileModerationStatus(db, input.uid);
  return {decision: input.decision, actionId, replayed: false, status: newStatus};
}
