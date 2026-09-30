import type {Query} from "firebase-admin/firestore";
import {ACTION_COLLECTION} from "./actions/actionTypes.js";
import {AUDIT_COLLECTION} from "./audit/auditService.js";
import type {AdminActor} from "./auth/adminAuthorization.js";
import type {Permission} from "./auth/permissions.js";
import {ACTIVE_CASE_STATUSES, CASE_COLLECTION} from "./cases/caseTypes.js";
import type {AdminDeps} from "./deps.js";
import {AdminError} from "./errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "./validation.js";

/**
 * Dashboard counters. Each is a count() aggregation over an indexed filter —
 * billed per 1,000 index entries, never a document download — and each is
 * only computed when the caller holds the permission for that queue.
 */

async function count(query: Query): Promise<number | null> {
  try {
    const snap = await query.count().get();
    return snap.data().count;
  } catch {
    // A missing index must not take the whole dashboard down.
    return null;
  }
}

export async function getDashboard(deps: AdminDeps, actor: AdminActor) {
  const {db} = deps;
  const has = (p: Permission) => actor.permissions.has(p);
  const cases = db.collection(CASE_COLLECTION);
  const active = [...ACTIVE_CASE_STATUSES];
  const tasks: Record<string, Promise<number | null>> = {};
  if (has("case.read")) {
    tasks.openCases = count(cases.where("status", "in", active));
    tasks.criticalCases = count(cases.where("priority", "==", "critical").where("status", "in", active));
    tasks.highPriorityCases = count(cases.where("priority", "==", "high").where("status", "in", active));
    tasks.myCases = count(cases.where("assignedTo", "==", actor.uid).where("status", "in", active));
    tasks.verificationReviewCases = count(cases.where("type", "==", "VERIFICATION_REVIEW").where("status", "in", active));
  }
  if (has("report.read")) {
    tasks.openReports = count(db.collection("reports").where("status", "==", "open"));
  }
  if (has("photo.read")) {
    tasks.photoManualReview = count(db.collectionGroup("photoModeration").where("status", "==", "manual_review"));
  }
  if (has("humor.read")) {
    tasks.humorReview = count(db.collection("humorModerationQueue").where("status", "==", "needs_review"));
  }
  if (has("verification.read")) {
    tasks.verificationInReview = count(db.collectionGroup("verification").where("status", "==", "in_review"));
  }
  if (has("automation.read") || has("automation.review")) {
    tasks.automationManualReview = count(db.collection("automationJobs").where("status", "==", "manual_review"));
  }
  if (has("appeal.read")) {
    tasks.openAppeals = count(db.collection("appeals").where("status", "in", ["open", "in_review"]));
  }
  if (has("support.read")) {
    const tickets = db.collection("supportTickets");
    tasks.openSupportTickets = count(tickets.where("status", "in", ["open", "Open", "in_progress", "InProgress"]));
    tasks.urgentSupportTickets = Promise.all([
      count(tickets.where("priority", "==", "urgent").where("status", "in", ["open", "Open", "in_progress", "InProgress"])),
      count(tickets.where("priority", "==", "Urgent").where("status", "in", ["open", "Open", "in_progress", "InProgress"])),
    ]).then(([a, b]) => (a === null && b === null ? null : (a ?? 0) + (b ?? 0)));
  }
  const keys = Object.keys(tasks);
  const values = await Promise.all(keys.map((k) => tasks[k]));
  const counters = Object.fromEntries(keys.map((k, i) => [k, values[i]]));

  let recentActions: Array<Record<string, unknown>> = [];
  if (has("user.read")) {
    const snap = await db.collection(ACTION_COLLECTION).orderBy("createdAt", "desc").limit(10).get();
    recentActions = snap.docs.map((doc) => ({
      actionId: doc.id,
      type: doc.get("type") ?? null,
      targetUserId: doc.get("targetUserId") ?? null,
      reasonCode: doc.get("reasonCode") ?? null,
      actorAdminId: doc.get("actorAdminId") ?? null,
      createdAt: iso(doc.get("createdAt")),
    }));
  }
  return {counters, recentActions, generatedAt: new Date(deps.now()).toISOString()};
}

export async function listAuditEvents(
  deps: AdminDeps,
  input: {actorAdminId: string | null; targetId: string | null; action: string | null; cursor: unknown; limit: number},
) {
  const filters = [input.actorAdminId, input.targetId, input.action].filter(Boolean);
  if (filters.length > 1) {
    // One filter at a time keeps every query on a single composite index.
    throw new AdminError("invalid_argument", "one_filter_at_a_time");
  }
  let q: Query = deps.db.collection(AUDIT_COLLECTION);
  if (input.actorAdminId) {
    q = q.where("actorAdminId", "==", input.actorAdminId);
  } else if (input.targetId) {
    q = q.where("targetId", "==", input.targetId);
  } else if (input.action) {
    q = q.where("action", "==", input.action);
  }
  q = q.orderBy("createdAt", "desc").orderBy("__name__", "desc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: snap.docs.map((doc) => ({
      eventId: doc.id,
      action: doc.get("action") ?? null,
      actorAdminId: doc.get("actorAdminId") ?? null,
      actorRole: doc.get("actorRole") ?? null,
      targetType: doc.get("targetType") ?? null,
      targetId: doc.get("targetId") ?? null,
      caseId: doc.get("caseId") ?? null,
      actionId: doc.get("actionId") ?? null,
      requestId: doc.get("requestId") ?? null,
      metadata: doc.get("metadata") ?? {},
      createdAt: iso(doc.get("createdAt")),
    })),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("createdAt")), last.id])
      : null,
  };
}
