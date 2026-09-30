import type {DocumentData, Query} from "firebase-admin/firestore";
import {ACTION_COLLECTION} from "../actions/actionTypes.js";
import {STAFF_COLLECTION, parseStaffRecord, type AdminActor} from "../auth/adminAuthorization.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "../validation.js";
import {loadUserCards} from "../users/userCards.js";
import {
  ACTIVE_CASE_STATUSES,
  CASE_COLLECTION,
  type CaseStatus,
  type CaseType,
} from "./caseTypes.js";

/**
 * Case queue reads. The active queue sorts by priority, then age; closed
 * cases sort by resolution time. Every list is cursor-paginated and every
 * filter combination is backed by a composite index in
 * firebase/firestore.indexes.json.
 */

export type CaseListStatus = "active" | CaseStatus;

export function caseRow(id: string, data: DocumentData) {
  return {
    caseId: id,
    type: data.type ?? null,
    status: data.status ?? "open",
    priority: data.priority ?? "normal",
    subjectUserId: data.subjectUserId ?? null,
    subjectRef: data.subjectRef ?? null,
    reasonCodes: Array.isArray(data.reasonCodes) ? data.reasonCodes.slice(0, 10) : [],
    sourceCount: typeof data.sourceCount === "number" ? data.sourceCount : 0,
    reporterCount: typeof data.reporterCount === "number" ? data.reporterCount : 0,
    assignedTo: data.assignedTo ?? null,
    escalated: data.escalated === true,
    escalationLevel: typeof data.escalationLevel === "number" ? data.escalationLevel : 0,
    summary: data.summary ?? null,
    createdAt: iso(data.createdAt),
    updatedAt: iso(data.updatedAt),
    lastActivityAt: iso(data.lastActivityAt),
    resolvedAt: iso(data.resolvedAt),
    resolvedBy: data.resolvedBy ?? null,
    resolution: data.resolution ?? null,
  };
}

export async function listCases(
  deps: AdminDeps,
  actor: AdminActor,
  input: {status: CaseListStatus; type: CaseType | null; assigned: "me" | "any"; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q: Query = db.collection(CASE_COLLECTION);
  if (input.type) {
    q = q.where("type", "==", input.type);
  }
  if (input.assigned === "me") {
    q = q.where("assignedTo", "==", actor.uid);
  }
  const active = input.status === "active" || ACTIVE_CASE_STATUSES.includes(input.status as CaseStatus);
  q = input.status === "active"
    ? q.where("status", "in", [...ACTIVE_CASE_STATUSES])
    : q.where("status", "==", input.status);
  let arity: number;
  if (active) {
    q = q.orderBy("priorityRank", "desc").orderBy("createdAt", "asc").orderBy("__name__", "asc");
    arity = 3;
  } else {
    q = q.orderBy("resolvedAt", "desc").orderBy("__name__", "desc");
    arity = 2;
  }
  const after = decodeCursor(input.cursor, arity);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const rows = snap.docs.map((doc) => caseRow(doc.id, doc.data()));
  const cards = await loadUserCards(db, rows.map((r) => r.subjectUserId), deps.now());
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: rows.map((row) => ({...row, subject: row.subjectUserId ? cards.get(row.subjectUserId) ?? null : null})),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor(arity === 3
        ? [cursorPart(last.get("priorityRank")), cursorPart(last.get("createdAt")), last.id]
        : [cursorPart(last.get("resolvedAt")), last.id])
      : null,
  };
}

/** A source record, projected for the case screen. */
async function sourceSummary(deps: AdminDeps, ref: string): Promise<Record<string, unknown>> {
  const {db} = deps;
  const segments = ref.split("/");
  if (segments.length % 2 !== 0 || segments.some((s) => !s)) {
    return {ref, kind: "unknown"};
  }
  const snap = await db.doc(ref).get();
  if (!snap.exists) {
    return {ref, kind: segments[segments.length - 2], exists: false};
  }
  const data = snap.data() ?? {};
  switch (segments[0] === "users" ? segments[2] : segments[0]) {
  case "reports":
    return {
      ref,
      kind: "report",
      exists: true,
      reason: data.reason ?? null,
      priority: data.priority ?? null,
      status: data.status ?? null,
      reporterId: data.reporterId ?? null,
      description: typeof data.description === "string" ? data.description.slice(0, 2000) : null,
      // Metadata only; chats are end-to-end encrypted and never decrypted.
      matchId: data.matchId ?? null,
      messageId: data.messageId ?? null,
      createdAt: iso(data.createdAt),
    };
  case "photoModeration":
    return {
      ref,
      kind: "photo",
      exists: true,
      uid: segments[1],
      imageId: segments[3],
      status: data.status ?? null,
      reason: data.reason ?? null,
      moderatedBy: data.moderatedBy ?? null,
      updatedAt: iso(data.updatedAt),
    };
  case "verification":
    return {
      ref,
      kind: "verification",
      exists: true,
      provider: data.provider ?? null,
      status: data.status ?? null,
      reason: data.reason ?? null,
      updatedAt: iso(data.updatedAt),
    };
  case "supportTickets":
    return {
      ref,
      kind: "support_ticket",
      exists: true,
      subject: typeof data.subject === "string" ? data.subject.slice(0, 200) : null,
      status: data.status ?? null,
      category: data.category ?? null,
      createdAt: iso(data.createdAt),
    };
  case "appeals":
    return {
      ref,
      kind: "appeal",
      exists: true,
      status: data.status ?? null,
      actionType: data.actionType ?? null,
      reason: typeof data.reason === "string" ? data.reason.slice(0, 2000) : null,
      createdAt: iso(data.createdAt),
    };
  case "automationJobs":
    return {
      ref,
      kind: "automation_job",
      exists: true,
      jobKind: data.kind ?? null,
      status: data.status ?? null,
      error: typeof data.error === "string" ? data.error.slice(0, 300) : null,
    };
  case "humorModerationQueue":
    return {ref, kind: "humor", exists: true, status: data.status ?? null, reportCount: data.reportCount ?? 0};
  default:
    return {ref, kind: segments[segments.length - 2], exists: true};
  }
}

export async function getCase(deps: AdminDeps, caseId: string) {
  const {db} = deps;
  const ref = db.doc(`${CASE_COLLECTION}/${caseId}`);
  const [snap, notes] = await Promise.all([
    ref.get(),
    ref.collection("notes").orderBy("createdAt", "asc").limit(200).get(),
  ]);
  if (!snap.exists) {
    throw new AdminError("not_found", "case");
  }
  const row = caseRow(snap.id, snap.data() ?? {});
  const sourceRefs = (Array.isArray(snap.get("sourceRefs")) ? (snap.get("sourceRefs") as string[]) : []).slice(0, 25);
  const actionIds = (Array.isArray(snap.get("actionIds")) ? (snap.get("actionIds") as string[]) : []).slice(0, 25);
  const [sources, actions, cards] = await Promise.all([
    Promise.all(sourceRefs.map((r) => sourceSummary(deps, r))),
    actionIds.length ? db.getAll(...actionIds.map((id) => db.doc(`${ACTION_COLLECTION}/${id}`))) : Promise.resolve([]),
    loadUserCards(db, [row.subjectUserId], deps.now()),
  ]);
  const staffIds = [...new Set([
    row.assignedTo,
    ...notes.docs.map((n) => n.get("authorUid")),
  ].filter((u): u is string => typeof u === "string" && u !== "system"))];
  const staffDocs = staffIds.length ? await db.getAll(...staffIds.map((u) => db.doc(`${STAFF_COLLECTION}/${u}`))) : [];
  const staffNames = new Map(staffDocs.map((s) => [s.id, parseStaffRecord(s.id, s.data())?.displayName ?? null]));
  let verification: Record<string, unknown> | null = null;
  if (row.subjectUserId) {
    const v = await db.doc(`users/${row.subjectUserId}/verification/identity`).get();
    verification = v.exists
      ? {status: v.get("status") ?? null, provider: v.get("provider") ?? null, verifiedAt: iso(v.get("verifiedAt"))}
      : {status: "not_started"};
  }
  return {
    ...row,
    subject: row.subjectUserId ? cards.get(row.subjectUserId) ?? null : null,
    assigneeName: row.assignedTo ? staffNames.get(row.assignedTo) ?? null : null,
    verification,
    sources,
    moreSources: Math.max(0, row.sourceCount - sourceRefs.length),
    actions: actions.filter((a) => a.exists).map((a) => ({
      actionId: a.id,
      type: a.get("type") ?? null,
      reasonCode: a.get("reasonCode") ?? null,
      actorAdminId: a.get("actorAdminId") ?? null,
      createdAt: iso(a.get("createdAt")),
      overturnedByActionId: a.get("overturnedByActionId") ?? null,
    })),
    timeline: notes.docs.map((n) => ({
      noteId: n.id,
      type: n.get("type") ?? "system_event",
      event: n.get("event") ?? null,
      authorUid: n.get("authorUid") ?? null,
      authorName: staffNames.get(String(n.get("authorUid") ?? "")) ?? null,
      text: typeof n.get("text") === "string" ? n.get("text") : null,
      detail: n.get("detail") ?? null,
      createdAt: iso(n.get("createdAt")),
    })),
  };
}
