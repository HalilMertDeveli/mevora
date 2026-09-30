import {FieldValue, type DocumentData} from "firebase-admin/firestore";
import {appendAuditEvent} from "../audit/auditService.js";
import type {AdminActor} from "../auth/adminAuthorization.js";
import {openOrAttachCase} from "../cases/caseService.js";
import {PRIORITY_RANK, RESOLUTION_CODES, type ResolutionCode} from "../cases/caseTypes.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "../validation.js";
import {loadUserCards} from "../users/userCards.js";
import {reportCorrelationKey, reportPriority} from "./reportPriority.js";

/**
 * The user-report queue over the existing `reports` collection.
 *
 * Reports keep the shape reportUser has always written; the queue reads them
 * as they are and adds only server-owned fields (priority, caseId,
 * resolution). The open queue is ordered by priority then age, so a critical
 * report filed a minute ago sits above a normal one filed yesterday.
 */

export const REPORT_QUEUE_STATUSES = ["open", "resolved", "dismissed", "all"] as const;
export type ReportQueueStatus = (typeof REPORT_QUEUE_STATUSES)[number];

function reportRow(id: string, data: DocumentData) {
  const {priority} = typeof data.priority === "string"
    ? {priority: data.priority as string}
    : reportPriority(data.reason);
  return {
    reportId: id,
    reason: data.reason ?? "other",
    priority,
    status: data.status ?? "open",
    createdAt: iso(data.createdAt),
    reportedUserId: data.reportedUserId ?? null,
    reporterId: data.reporterId ?? null,
    description: typeof data.description === "string" ? data.description.slice(0, 2000) : null,
    // Operational references only. There is no endpoint that turns a
    // messageId into message content: chats are end-to-end encrypted.
    matchId: data.matchId ?? null,
    messageId: data.messageId ?? null,
    caseId: data.caseId ?? null,
    resolution: data.resolution ?? null,
    resolvedAt: iso(data.resolvedAt),
    resolvedBy: data.resolvedBy ?? null,
  };
}

export async function listReports(
  deps: AdminDeps,
  input: {status: ReportQueueStatus; reportedUserId: string | null; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q;
  let arity: number;
  if (input.reportedUserId) {
    q = db.collection("reports").where("reportedUserId", "==", input.reportedUserId).orderBy("createdAt", "desc").orderBy("__name__", "desc");
    arity = 2;
  } else if (input.status === "open") {
    // Reports written before priorityRank existed are backfilled by
    // adminBackfillReportPriority; until then they surface in the "all" view.
    q = db.collection("reports")
      .where("status", "==", "open")
      .orderBy("priorityRank", "desc")
      .orderBy("createdAt", "asc")
      .orderBy("__name__", "asc");
    arity = 3;
  } else if (input.status === "all") {
    q = db.collection("reports").orderBy("createdAt", "desc").orderBy("__name__", "desc");
    arity = 2;
  } else {
    q = db.collection("reports").where("status", "==", input.status).orderBy("createdAt", "desc").orderBy("__name__", "desc");
    arity = 2;
  }
  const after = decodeCursor(input.cursor, arity);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const rows = snap.docs.map((doc) => reportRow(doc.id, doc.data()));
  const cards = await loadUserCards(db, rows.flatMap((r) => [r.reportedUserId, r.reporterId]), deps.now());
  const caseIds = [...new Set(rows.map((r) => r.caseId).filter((id): id is string => typeof id === "string"))];
  const cases = caseIds.length ? await db.getAll(...caseIds.map((id) => db.doc(`moderationCases/${id}`))) : [];
  const caseMap = new Map(cases.map((c) => [c.id, c.data()]));
  const last = snap.docs[snap.docs.length - 1];
  const nextCursor = snap.docs.length === input.limit && last
    ? encodeCursor(arity === 3
      ? [cursorPart(last.get("priorityRank")), cursorPart(last.get("createdAt")), last.id]
      : [cursorPart(last.get("createdAt")), last.id])
    : null;
  return {
    items: rows.map((row) => ({
      ...row,
      reportedUser: row.reportedUserId ? cards.get(row.reportedUserId) ?? null : null,
      reporter: row.reporterId ? cards.get(row.reporterId) ?? null : null,
      caseStatus: row.caseId ? caseMap.get(row.caseId)?.status ?? null : null,
      assignedTo: row.caseId ? caseMap.get(row.caseId)?.assignedTo ?? null : null,
    })),
    nextCursor,
  };
}

/**
 * Closes a single report. Most reports close through their case (resolving a
 * USER_REPORT case closes every open report it holds); this is for the odd
 * one out — a duplicate, or a report filed against the wrong member.
 */
export async function resolveUserReport(
  deps: AdminDeps,
  actor: AdminActor,
  input: {reportId: string; outcome: "resolved" | "dismissed"; code: ResolutionCode; note: string | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  if (!(RESOLUTION_CODES as readonly string[]).includes(input.code)) {
    throw new AdminError("invalid_argument", "code");
  }
  const ref = db.doc(`reports/${input.reportId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new AdminError("not_found", "report");
    }
    const status = String(snap.get("status") ?? "open");
    if (status !== "open") {
      if (status === input.outcome && snap.get("resolution") === input.code) {
        return {reportId: input.reportId, status, replayed: true};
      }
      throw new AdminError("invalid_state_transition", "invalid_state_transition", {from: status});
    }
    tx.set(ref, {
      status: input.outcome,
      resolution: input.code,
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "REPORT_RESOLVED",
      targetType: "report",
      targetId: input.reportId,
      caseId: (snap.get("caseId") as string | undefined) ?? null,
      requestId,
      metadata: {
        outcome: input.outcome,
        code: input.code,
        reportedUserId: snap.get("reportedUserId") ?? null,
        internalNote: input.note ?? "",
      },
    }, nowMs);
    return {reportId: input.reportId, status: input.outcome, replayed: false};
  });
}

/** Opens (or joins) the case for a report that predates case intake. */
export async function openCaseForReport(
  deps: AdminDeps,
  actor: AdminActor,
  input: {reportId: string},
  requestId: string,
) {
  const {db} = deps;
  const snap = await db.doc(`reports/${input.reportId}`).get();
  if (!snap.exists) {
    throw new AdminError("not_found", "report");
  }
  const existing = snap.get("caseId");
  if (typeof existing === "string" && existing) {
    return {caseId: existing, created: false};
  }
  const reason = String(snap.get("reason") ?? "other");
  const reportedUserId = String(snap.get("reportedUserId") ?? "");
  if (!reportedUserId) {
    throw new AdminError("invalid_state_transition", "report_without_subject");
  }
  const {priority} = reportPriority(reason);
  const result = await openOrAttachCase(db, {
    type: "USER_REPORT",
    correlationKey: reportCorrelationKey(reportedUserId, reason),
    subjectUserId: reportedUserId,
    sourceRef: `reports/${input.reportId}`,
    reasonCode: reason,
    priority,
    reporterId: (snap.get("reporterId") as string | undefined) ?? null,
    summary: `User report: ${reason}`,
    createdBy: actor.uid,
    createdByRole: actor.role,
    requestId,
  }, deps.now());
  await db.doc(`reports/${input.reportId}`).set({
    caseId: result.caseId,
    priority,
    priorityRank: PRIORITY_RANK[priority],
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {caseId: result.caseId, created: result.created};
}

/**
 * Bounded backfill: gives legacy reports (written before server-side
 * priority) a priority so they sort into the open queue. Idempotent; page
 * through with the returned cursor.
 */
export async function backfillReportPriority(
  deps: AdminDeps,
  input: {cursor: string | null; pageSize: number},
) {
  const {db} = deps;
  let q = db.collection("reports").orderBy("__name__").limit(input.pageSize);
  if (input.cursor) {
    q = q.startAfter(input.cursor);
  }
  const snap = await q.get();
  const batch = db.batch();
  let updated = 0;
  for (const doc of snap.docs) {
    if (typeof doc.get("priorityRank") === "number") {
      continue;
    }
    const {priority, priorityRank} = reportPriority(doc.get("reason"));
    batch.set(doc.ref, {priority, priorityRank}, {merge: true});
    updated += 1;
  }
  if (updated) {
    await batch.commit();
  }
  const last = snap.docs[snap.docs.length - 1];
  return {scanned: snap.size, updated, nextCursor: snap.size === input.pageSize && last ? last.id : null};
}
