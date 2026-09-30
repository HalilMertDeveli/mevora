import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {enqueueCloudTask} from "../../automation/tasksEnqueue.js";
import {JobKind, JobStatus} from "../../automation/types.js";
import {appendAuditEvent} from "../audit/auditService.js";
import {requirePermission, type AdminActor} from "../auth/adminAuthorization.js";
import {openOrAttachCase} from "../cases/caseService.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "../validation.js";

/**
 * Human review of automation jobs the pipeline could not settle
 * (`automationJobs` with status manual_review / failed) and of findings the
 * read-only audits filed in `adminReviewQueue`.
 *
 * There is no generic "retry everything" button. What a reviewer may do is
 * decided per job kind below, because some kinds are compliance obligations:
 * closing an account-deletion or identity-erasure job by hand asserts that a
 * member's data is really gone, so it needs automation.resolve_sensitive.
 */

export type JobReviewAction = "retry" | "resolve" | "dismiss" | "escalate";

interface JobPolicy {
  actions: readonly JobReviewAction[];
  /** resolve/dismiss need automation.resolve_sensitive. */
  sensitive: boolean;
  note: string;
}

export const JOB_REVIEW_POLICY: Readonly<Record<string, JobPolicy>> = {
  [JobKind.accountDeletionVerify]: {
    actions: ["retry", "resolve", "escalate"],
    sensitive: true,
    note: "Re-running verification is read-only and safe. Resolving asserts the deletion is complete.",
  },
  [JobKind.identityProviderErasure]: {
    actions: ["retry", "resolve", "escalate"],
    sensitive: true,
    note: "Retry re-sends the idempotent provider erasure request. Resolve only with provider confirmation.",
  },
  [JobKind.forgedBlockAudit]: {
    actions: ["resolve", "dismiss", "escalate"],
    sensitive: false,
    note: "Read-only audit. Findings are judged in adminReviewQueue; the audit is never re-run blindly.",
  },
};

const DEFAULT_POLICY: JobPolicy = {
  actions: ["escalate", "dismiss"],
  sensitive: false,
  note: "No automated retry is defined for this job kind.",
};

export function jobPolicy(kind: string): JobPolicy {
  return JOB_REVIEW_POLICY[kind] ?? DEFAULT_POLICY;
}

/** What this actor may do to this job, as the console should offer it. */
export function allowedJobActions(kind: string, actor: AdminActor): JobReviewAction[] {
  const policy = jobPolicy(kind);
  return policy.actions.filter((action) => {
    if (action === "escalate") {
      return actor.permissions.has("case.escalate") || actor.permissions.has("automation.review");
    }
    if (!actor.permissions.has("automation.review")) {
      return false;
    }
    if ((action === "resolve" || action === "dismiss") && policy.sensitive) {
      return actor.permissions.has("automation.resolve_sensitive");
    }
    return true;
  });
}

/** Result fields safe to show; everything else in a job result is dropped. */
const SAFE_RESULT_KEYS = ["complete", "issues", "flagged", "scanned", "outcome", "remaining", "nextCursor", "checkedAt"];

function safeResult(result: unknown): Record<string, unknown> | null {
  if (!result || typeof result !== "object") {
    return null;
  }
  const out: Record<string, unknown> = {};
  for (const key of SAFE_RESULT_KEYS) {
    const value = (result as Record<string, unknown>)[key];
    if (value === undefined) {
      continue;
    }
    out[key] = Array.isArray(value) ? value.slice(0, 20).map((v) => String(v).slice(0, 200)) : value;
  }
  return out;
}

function jobRow(id: string, data: DocumentData, actor: AdminActor) {
  const kind = String(data.kind ?? "");
  return {
    jobId: id,
    kind,
    status: data.status ?? null,
    attempts: typeof data.attempts === "number" ? data.attempts : 0,
    maxAttempts: typeof data.maxAttempts === "number" ? data.maxAttempts : null,
    error: typeof data.error === "string" ? data.error.slice(0, 300) : null,
    createdBy: data.createdBy ?? null,
    createdAt: iso(data.createdAt),
    updatedAt: iso(data.updatedAt),
    // The member a compliance job concerns — uid only.
    subjectUid: typeof data.payload?.uid === "string" ? data.payload.uid : null,
    result: safeResult(data.result),
    adminReview: data.adminReview
      ? {action: data.adminReview.action ?? null, by: data.adminReview.by ?? null, at: iso(data.adminReview.at)}
      : null,
    policyNote: jobPolicy(kind).note,
    allowedActions: allowedJobActions(kind, actor),
  };
}

export async function listManualReviewJobs(
  deps: AdminDeps,
  actor: AdminActor,
  input: {status: "manual_review" | "failed"; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q = db.collection("automationJobs")
    .where("status", "==", input.status)
    .orderBy("updatedAt", "desc")
    .orderBy("__name__", "desc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const [snap, reviewItems] = await Promise.all([
    q.limit(input.limit).get(),
    db.collection("adminReviewQueue").where("status", "==", "open").limit(25).get(),
  ]);
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: snap.docs.map((doc) => jobRow(doc.id, doc.data(), actor)),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("updatedAt")), last.id])
      : null,
    reviewItems: reviewItems.docs.map((doc) => ({
      itemId: doc.id,
      kind: doc.get("kind") ?? doc.get("type") ?? null,
      status: doc.get("status") ?? null,
      remediation: doc.get("remediation") ?? null,
      createdAt: iso(doc.get("createdAt")),
      summary: typeof doc.get("summary") === "string" ? String(doc.get("summary")).slice(0, 300) : null,
    })),
  };
}

export async function reviewAutomationJob(
  deps: AdminDeps,
  actor: AdminActor,
  input: {jobId: string; action: JobReviewAction; note: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const ref = db.doc(`automationJobs/${input.jobId}`);

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new AdminError("not_found", "job");
    }
    const kind = String(snap.get("kind") ?? "");
    const status = String(snap.get("status") ?? "");
    if (!allowedJobActions(kind, actor).includes(input.action)) {
      // Distinguish "no permission" from "not a thing this kind supports".
      if (jobPolicy(kind).actions.includes(input.action)) {
        requirePermission(actor, jobPolicy(kind).sensitive ? "automation.resolve_sensitive" : "automation.review");
      }
      throw new AdminError("unsupported_job_action", "unsupported_job_action", {kind, action: input.action});
    }
    const reviewable = status === JobStatus.manual_review || status === JobStatus.failed;
    if (!reviewable) {
      throw new AdminError("invalid_state_transition", "invalid_state_transition", {from: status});
    }
    const review = {action: input.action, by: actor.uid, at: Timestamp.fromMillis(nowMs)};
    if (input.action === "retry") {
      const attempts = typeof snap.get("attempts") === "number" ? Number(snap.get("attempts")) : 0;
      tx.set(ref, {
        status: JobStatus.retrying,
        requiresHumanReview: false,
        // A fresh, bounded budget: three more tries, then back to a human.
        maxAttempts: attempts + 3,
        nextRetryAt: Timestamp.fromMillis(nowMs),
        adminReview: review,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else if (input.action === "resolve") {
      tx.set(ref, {
        status: JobStatus.resolved,
        requiresHumanReview: false,
        adminReview: review,
        resolvedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else if (input.action === "dismiss") {
      tx.set(ref, {
        status: JobStatus.cancelled,
        requiresHumanReview: false,
        adminReview: review,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      tx.set(ref, {adminReview: review, escalatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: input.action === "retry"
        ? "AUTOMATION_JOB_RETRIED"
        : input.action === "resolve"
          ? "AUTOMATION_JOB_RESOLVED"
          : input.action === "dismiss"
            ? "AUTOMATION_JOB_DISMISSED"
            : "AUTOMATION_JOB_ESCALATED",
      targetType: "automation_job",
      targetId: input.jobId,
      requestId,
      metadata: {kind, fromStatus: status, internalNote: input.note},
    }, nowMs);
    return {kind, subjectUid: typeof snap.get("payload")?.uid === "string" ? String(snap.get("payload").uid) : null};
  });

  let caseId: string | null = null;
  if (input.action === "retry") {
    await enqueueCloudTask(input.jobId);
  }
  if (input.action === "escalate") {
    ({caseId} = await openOrAttachCase(db, {
      type: "AUTOMATION_REVIEW",
      correlationKey: `automation:${input.jobId}`,
      subjectUserId: outcome.subjectUid,
      sourceRef: `automationJobs/${input.jobId}`,
      reasonCode: outcome.kind,
      priority: jobPolicy(outcome.kind).sensitive ? "high" : "medium",
      summary: `Automation job needs review: ${outcome.kind}`,
      createdBy: actor.uid,
      createdByRole: actor.role,
      requestId,
    }, nowMs));
  }
  return {jobId: input.jobId, action: input.action, caseId};
}

export async function resolveReviewItem(
  deps: AdminDeps,
  actor: AdminActor,
  input: {itemId: string; outcome: "resolved" | "dismissed"; note: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const ref = db.doc(`adminReviewQueue/${input.itemId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new AdminError("not_found", "review_item");
    }
    if (snap.get("status") !== "open" && snap.get("status") !== "in_review") {
      throw new AdminError("invalid_state_transition", "invalid_state_transition", {from: snap.get("status")});
    }
    tx.set(ref, {
      status: input.outcome,
      resolvedBy: actor.uid,
      resolvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "REVIEW_ITEM_RESOLVED",
      targetType: "review_item",
      targetId: input.itemId,
      requestId,
      metadata: {outcome: input.outcome, internalNote: input.note},
    }, nowMs);
    return {itemId: input.itemId, status: input.outcome};
  });
}
