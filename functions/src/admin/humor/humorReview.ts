import {applyHumorModerationDecision} from "../../humor/reports.js";
import {recordAuditEvent} from "../audit/auditService.js";
import type {AdminActor} from "../auth/adminAuthorization.js";
import {openOrAttachCase} from "../cases/caseService.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "../validation.js";

/**
 * Humor Lab moderation, surfaced in the console.
 *
 * The queue is the existing `humorModerationQueue`; decisions go through the
 * existing applyHumorModerationDecision, the same code runHumorModeration
 * calls. There is no second humor moderation implementation here — this
 * module only lists, hydrates, audits and escalates.
 */

export const HUMOR_QUEUE_STATUSES = ["needs_review", "pending", "rejected", "approved"] as const;
export type HumorQueueStatus = (typeof HUMOR_QUEUE_STATUSES)[number];

function previewUrl(content: Record<string, unknown> | undefined): string | null {
  if (!content) {
    return null;
  }
  const media = content.media as Record<string, unknown> | undefined;
  const candidates = [media?.thumbUrl, media?.downloadUrl];
  const url = candidates.find((c) => typeof c === "string" && /^https:\/\//.test(c));
  return typeof url === "string" ? url : null;
}

export async function listHumorReviews(
  deps: AdminDeps,
  input: {status: HumorQueueStatus; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q = db.collection("humorModerationQueue")
    .where("status", "==", input.status)
    .orderBy("updatedAt", input.status === "needs_review" ? "asc" : "desc")
    .orderBy("__name__", input.status === "needs_review" ? "asc" : "desc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const ids = snap.docs.map((d) => d.id);
  const contents = ids.length ? await db.getAll(...ids.map((id) => db.doc(`humorContent/${id}`))) : [];
  const contentMap = new Map(contents.map((c) => [c.id, c.data()]));
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: snap.docs.map((doc) => {
      const content = contentMap.get(doc.id);
      return {
        contentId: doc.id,
        status: doc.get("status") ?? null,
        source: doc.get("source") ?? null,
        reportCount: typeof doc.get("reportCount") === "number" ? doc.get("reportCount") : 0,
        lastReportedAt: iso(doc.get("lastReportedAt")),
        updatedAt: iso(doc.get("updatedAt")),
        moderatedAt: iso(doc.get("moderatedAt")),
        content: content
          ? {
            textBody: typeof (content.media as Record<string, unknown> | undefined)?.textBody === "string"
              ? String((content.media as Record<string, unknown>).textBody).slice(0, 500)
              : null,
            type: content.type ?? null,
            category: content.category ?? null,
            language: content.language ?? null,
            active: content.active === true,
            safetyStatus: content.safetyStatus ?? null,
            safetyFlags: content.safetyFlags ?? {},
            provider: (content.source as Record<string, unknown> | undefined)?.provider ?? null,
            previewUrl: previewUrl(content),
          }
          : null,
      };
    }),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("updatedAt")), last.id])
      : null,
  };
}

export async function getHumorReports(deps: AdminDeps, contentId: string) {
  const snap = await deps.db.collection("humorReports").where("contentId", "==", contentId).limit(20).get();
  return snap.docs.map((doc) => ({
    reportId: doc.id,
    reason: doc.get("reason") ?? null,
    details: typeof doc.get("details") === "string" ? String(doc.get("details")).slice(0, 500) : null,
    status: doc.get("status") ?? null,
    createdAt: iso(doc.get("createdAt")),
  }));
}

export async function reviewHumorContent(
  deps: AdminDeps,
  actor: AdminActor,
  input: {contentId: string; decision: "approve" | "reject" | "escalate"; note: string | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  if (input.decision === "escalate") {
    const queue = await db.doc(`humorModerationQueue/${input.contentId}`).get();
    if (!queue.exists) {
      throw new AdminError("not_found", "humor_content");
    }
    const result = await openOrAttachCase(db, {
      type: "HUMOR_REVIEW",
      correlationKey: `humor:${input.contentId}`,
      subjectRef: `humorContent/${input.contentId}`,
      sourceRef: `humorModerationQueue/${input.contentId}`,
      priority: "medium",
      summary: "Humor content escalated",
      createdBy: actor.uid,
      createdByRole: actor.role,
      requestId,
    }, nowMs);
    await recordAuditEvent(db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "HUMOR_ESCALATED",
      targetType: "humor_content",
      targetId: input.contentId,
      caseId: result.caseId,
      requestId,
      metadata: {internalNote: input.note ?? ""},
    }, nowMs);
    return {contentId: input.contentId, caseId: result.caseId};
  }
  // The existing authority decides: same code path as runHumorModeration.
  const outcome = await applyHumorModerationDecision(db, actor.uid, {
    contentId: input.contentId,
    forceStatus: input.decision === "approve" ? "approved" : "rejected",
  });
  await recordAuditEvent(db, {
    actorAdminId: actor.uid,
    actorRole: actor.role,
    action: input.decision === "approve" ? "HUMOR_APPROVED" : "HUMOR_REJECTED",
    targetType: "humor_content",
    targetId: input.contentId,
    requestId,
    metadata: {
      safetyStatus: outcome.safetyStatus,
      active: outcome.active,
      resolvedReports: outcome.resolvedReports,
      internalNote: input.note ?? "",
    },
  }, nowMs);
  return outcome;
}
