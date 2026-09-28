import {FieldValue, type DocumentReference, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {classifyHumorSafety, emptySafetyFlags, isHumorSafetyStatus} from "./moderation.js";
import type {HumorSafetyFlags, HumorSafetyStatus} from "./types.js";

/**
 * Firestore document id shape accepted for a humor content id. It is
 * interpolated into `humorContent/`, `humorReports/`, `humorModerationQueue/`
 * and `users/{uid}/humorInteractions/` paths, so a `/` must never get through.
 */
const HUMOR_CONTENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export const HUMOR_REPORT_REASONS = ["offensive", "spam", "misleading", "other"] as const;
export type HumorReportReason = (typeof HUMOR_REPORT_REASONS)[number];

const MAX_REPORT_DETAILS = 500;
const BATCH_LIMIT = 400;

export function parseHumorContentId(raw: unknown): string {
  const contentId = typeof raw === "string" ? raw.trim() : "";
  if (!HUMOR_CONTENT_ID_PATTERN.test(contentId)) {
    throw new HttpsError("invalid-argument", "contentId");
  }
  return contentId;
}

function parseReportReason(raw: unknown): HumorReportReason {
  return typeof raw === "string" &&
    (HUMOR_REPORT_REASONS as readonly string[]).includes(raw)
    ? (raw as HumorReportReason)
    : "other";
}

function parseReportDetails(raw: unknown): string {
  return typeof raw === "string" ? raw.trim().slice(0, MAX_REPORT_DETAILS) : "";
}

/** An admin has already ruled on this queue entry; a report must not undo it. */
function hasModerationDecision(queue: Record<string, unknown> | undefined): boolean {
  if (!queue) {
    return false;
  }
  return (
    (typeof queue.moderatedBy === "string" && queue.moderatedBy.length > 0) ||
    queue.status === "approved" ||
    queue.status === "rejected"
  );
}

/**
 * A user reports a humor item.
 *
 * - The report is create-only: a repeat report by the same user changes
 *   nothing (no reset of `createdAt` or of a resolved status, no second count).
 * - The queue counts distinct reports and is moved to `needs_review` only while
 *   no admin decision exists.
 * - A per-user marker on `users/{uid}/humorInteractions/{contentId}` keeps the
 *   item out of the reporter's feed and calibration from now on. It never
 *   touches an existing rating, and it has no profile or calibration effect.
 */
export async function submitHumorReport(
  db: Firestore,
  uid: string,
  data: Record<string, unknown>,
): Promise<{ok: true}> {
  const contentId = parseHumorContentId(data.contentId);
  const reason = parseReportReason(data.reason);
  const details = parseReportDetails(data.details);
  const reportId = `${uid}_${contentId}`;
  const contentRef = db.doc(`humorContent/${contentId}`);
  const reportRef = db.doc(`humorReports/${reportId}`);
  const queueRef = db.doc(`humorModerationQueue/${contentId}`);
  const markerRef = db.doc(`users/${uid}/humorInteractions/${contentId}`);

  await db.runTransaction(async (tx) => {
    const [contentSnap, reportSnap, queueSnap, markerSnap] = await Promise.all([
      tx.get(contentRef),
      tx.get(reportRef),
      tx.get(queueRef),
      tx.get(markerRef),
    ]);
    if (!contentSnap.exists) {
      throw new HttpsError("not-found", "content");
    }
    const now = FieldValue.serverTimestamp();
    if (!reportSnap.exists) {
      tx.set(reportRef, {
        reportId,
        reporterId: uid,
        contentId,
        reason,
        details,
        status: "open",
        createdAt: now,
        updatedAt: now,
      });
      if (!queueSnap.exists) {
        tx.set(queueRef, {
          contentId,
          status: "needs_review",
          source: "user_report",
          reportCount: 1,
          lastReporterId: uid,
          lastReportedAt: now,
          createdAt: now,
          updatedAt: now,
        });
      } else {
        tx.set(
          queueRef,
          {
            contentId,
            reportCount: FieldValue.increment(1),
            lastReporterId: uid,
            lastReportedAt: now,
            updatedAt: now,
            ...(hasModerationDecision(queueSnap.data()) ? {} : {status: "needs_review"}),
          },
          {merge: true},
        );
      }
    }
    tx.set(
      markerRef,
      {
        contentId,
        reported: true,
        updatedAt: now,
        ...(markerSnap.exists ? {} : {skipped: true, createdAt: now}),
      },
      {merge: true},
    );
  });
  return {ok: true};
}

function isFinalDecision(status: HumorSafetyStatus): boolean {
  return status === "approved" || status === "rejected";
}

async function resolveOpenReports(
  db: Firestore,
  contentId: string,
  resolution: HumorSafetyStatus,
  adminUid: string,
): Promise<number> {
  const snap = await db.collection("humorReports").where("contentId", "==", contentId).get();
  const open: DocumentReference[] = snap.docs
    .filter((doc) => doc.data()?.status !== "resolved")
    .map((doc) => doc.ref);
  for (let i = 0; i < open.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const ref of open.slice(i, i + BATCH_LIMIT)) {
      batch.set(
        ref,
        {
          status: "resolved",
          resolution,
          resolvedBy: adminUid,
          resolvedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
    await batch.commit();
  }
  return open.length;
}

/**
 * Admin moderation of one humor item.
 *
 * - `forceStatus` must be a known safety status.
 * - Approval never re-activates an item an admin deactivated: an existing
 *   `active: false` holds unless the call passes `active: true`.
 * - A final decision (approved / rejected) resolves the item's open reports.
 */
export async function applyHumorModerationDecision(
  db: Firestore,
  adminUid: string,
  data: Record<string, unknown>,
): Promise<{
  ok: true;
  contentId: string;
  safetyStatus: HumorSafetyStatus;
  active: boolean;
  resolvedReports: number;
}> {
  const contentId = parseHumorContentId(data.contentId);
  const forced = data.forceStatus;
  if (forced !== undefined && forced !== null && !isHumorSafetyStatus(forced)) {
    throw new HttpsError("invalid-argument", "forceStatus");
  }
  const ref = db.doc(`humorContent/${contentId}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "content");
  }
  const existing = snap.data() ?? {};
  const suppliedFlags =
    data.safetyFlags && typeof data.safetyFlags === "object"
      ? (data.safetyFlags as Partial<HumorSafetyFlags>)
      : (existing.safetyFlags as Partial<HumorSafetyFlags> | undefined);
  const classified = classifyHumorSafety(emptySafetyFlags(suppliedFlags ?? {}));
  const safetyStatus: HumorSafetyStatus = isHumorSafetyStatus(forced)
    ? forced
    : classified.status;
  const active =
    safetyStatus === "approved" &&
    data.active !== false &&
    (data.active === true || existing.active !== false);

  const now = FieldValue.serverTimestamp();
  await ref.set(
    {
      safetyFlags: classified.flags,
      safetyStatus,
      active,
      updatedAt: now,
    },
    {merge: true},
  );
  await db.doc(`humorModerationQueue/${contentId}`).set(
    {
      contentId,
      status: safetyStatus,
      updatedAt: now,
      moderatedBy: adminUid,
      moderatedAt: now,
    },
    {merge: true},
  );
  const resolvedReports = isFinalDecision(safetyStatus)
    ? await resolveOpenReports(db, contentId, safetyStatus, adminUid)
    : 0;
  return {ok: true, contentId, safetyStatus, active, resolvedReports};
}
