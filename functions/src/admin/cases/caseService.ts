import {createHash, randomBytes} from "node:crypto";
import {
  FieldValue,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {appendAuditEvent} from "../audit/auditService.js";
import {requirePermission, STAFF_COLLECTION, parseStaffRecord, type AdminActor} from "../auth/adminAuthorization.js";
import {AdminError} from "../errors.js";
import {
  ACTIVE_CASE_STATUSES,
  CASE_COLLECTION,
  CASE_KEY_COLLECTION,
  MAX_SOURCE_REFS,
  PRIORITY_RANK,
  assertTransition,
  bumpPriority,
  isTerminalCaseStatus,
  maxPriority,
  parseCaseDoc,
  type CaseDoc,
  type CaseStatus,
  type CaseType,
  type Priority,
  type ResolutionCode,
} from "./caseTypes.js";

/**
 * Case workflow. Every state change is a transaction that re-reads the case,
 * so two moderators acting at once get deterministic outcomes: the first
 * commit wins and the second sees the new state (and a domain error) rather
 * than silently overwriting it.
 */

export function caseRef(db: Firestore, caseId: string): DocumentReference {
  return db.doc(`${CASE_COLLECTION}/${caseId}`);
}

export function caseKeyId(correlationKey: string): string {
  return createHash("sha256").update(correlationKey).digest("hex").slice(0, 40);
}

export function newCaseId(nowMs: number): string {
  return `case_${nowMs.toString(36)}_${randomBytes(5).toString("hex")}`;
}

function newNoteId(nowMs: number): string {
  return `note_${nowMs.toString(36).padStart(9, "0")}_${randomBytes(5).toString("hex")}`;
}

interface Writer {
  set(ref: DocumentReference, data: Record<string, unknown>, options?: {merge: boolean}): unknown;
  create(ref: DocumentReference, data: Record<string, unknown>): unknown;
}

/** A system event on the case timeline (not a moderator note). */
export function appendCaseEvent(
  writer: Writer,
  db: Firestore,
  caseId: string,
  event: {kind: string; actorUid: string; actorRole?: string | null; detail?: Record<string, unknown>},
  nowMs: number,
): void {
  const noteId = newNoteId(nowMs);
  writer.create(db.doc(`${CASE_COLLECTION}/${caseId}/notes/${noteId}`), {
    noteId,
    type: "system_event",
    event: event.kind,
    authorUid: event.actorUid,
    authorRole: event.actorRole ?? null,
    text: null,
    detail: event.detail ?? {},
    createdAt: FieldValue.serverTimestamp(),
  });
}

// ---------------------------------------------------------------------------
// Intake
// ---------------------------------------------------------------------------

export interface CaseIntake {
  type: CaseType;
  correlationKey: string;
  subjectUserId?: string | null;
  subjectRef?: string | null;
  sourceRef: string;
  reasonCode?: string | null;
  priority: Priority;
  reporterId?: string | null;
  summary?: string | null;
  /** Staff uid, or "system". */
  createdBy: string;
  createdByRole?: string | null;
  requestId?: string | null;
}

/**
 * Opens a case, or attaches the source to the matching open case.
 *
 * Correlation is keyed, not searched: `moderationCaseKeys/{hash(key)}` points
 * at the one open case for that key, read and written in the same
 * transaction, so concurrent intakes for the same key cannot create two cases.
 * When that case closes, the key is released and the next intake opens a
 * fresh case — a resolved case is never silently reopened.
 *
 * Keys are chosen by the caller so distinct safety concerns stay distinct:
 * user reports correlate on (subject, reason), never on subject alone, so an
 * `underage` report is never swallowed by an open `spam` case.
 *
 * Three or more distinct reporters on one case raise its priority one level.
 */
export async function openOrAttachCase(
  db: Firestore,
  intake: CaseIntake,
  nowMs: number,
): Promise<{caseId: string; created: boolean; attached: boolean}> {
  const keyRef = db.doc(`${CASE_KEY_COLLECTION}/${caseKeyId(intake.correlationKey)}`);
  return db.runTransaction(async (tx) => {
    const keySnap = await tx.get(keyRef);
    const existingId = typeof keySnap.data()?.caseId === "string" ? String(keySnap.data()?.caseId) : null;
    let existing: CaseDoc | null = null;
    if (existingId) {
      const snap = await tx.get(caseRef(db, existingId));
      existing = parseCaseDoc(existingId, snap.data());
      if (existing && isTerminalCaseStatus(existing.status)) {
        existing = null;
      }
    }

    if (existing) {
      if (existing.sourceRefs.includes(intake.sourceRef)) {
        return {caseId: existing.caseId, created: false, attached: false};
      }
      const reporterIds = intake.reporterId && !existing.reporterIds.includes(intake.reporterId)
        ? [...existing.reporterIds, intake.reporterId]
        : existing.reporterIds;
      let priority = maxPriority(existing.priority, intake.priority);
      if (reporterIds.length >= 3 && existing.reporterIds.length < 3) {
        priority = bumpPriority(priority);
      }
      tx.set(caseRef(db, existing.caseId), {
        ...(existing.sourceRefs.length < MAX_SOURCE_REFS
          ? {sourceRefs: FieldValue.arrayUnion(intake.sourceRef)}
          : {}),
        sourceCount: FieldValue.increment(1),
        ...(intake.reasonCode ? {reasonCodes: FieldValue.arrayUnion(intake.reasonCode)} : {}),
        ...(intake.reporterId && reporterIds.length <= MAX_SOURCE_REFS
          ? {reporterIds: FieldValue.arrayUnion(intake.reporterId)}
          : {}),
        reporterCount: reporterIds.length,
        priority,
        priorityRank: PRIORITY_RANK[priority],
        lastActivityAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      appendCaseEvent(tx, db, existing.caseId, {
        kind: "source_attached",
        actorUid: intake.createdBy,
        actorRole: intake.createdByRole,
        detail: {sourceRef: intake.sourceRef, reasonCode: intake.reasonCode ?? null, priority},
      }, nowMs);
      return {caseId: existing.caseId, created: false, attached: true};
    }

    const caseId = newCaseId(nowMs);
    tx.create(caseRef(db, caseId), {
      caseId,
      type: intake.type,
      subjectUserId: intake.subjectUserId ?? null,
      subjectRef: intake.subjectRef ?? null,
      sourceRefs: [intake.sourceRef],
      sourceCount: 1,
      reasonCodes: intake.reasonCode ? [intake.reasonCode] : [],
      reporterIds: intake.reporterId ? [intake.reporterId] : [],
      reporterCount: intake.reporterId ? 1 : 0,
      priority: intake.priority,
      priorityRank: PRIORITY_RANK[intake.priority],
      status: "open" satisfies CaseStatus,
      assignedTo: null,
      assignedAt: null,
      escalated: false,
      escalationLevel: 0,
      correlationKey: intake.correlationKey,
      actionIds: [],
      summary: intake.summary ?? null,
      createdBy: intake.createdBy,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastActivityAt: FieldValue.serverTimestamp(),
      resolvedAt: null,
      resolvedBy: null,
      resolution: null,
    });
    tx.set(keyRef, {
      caseId,
      correlationKey: intake.correlationKey,
      updatedAt: FieldValue.serverTimestamp(),
    });
    appendCaseEvent(tx, db, caseId, {
      kind: "created",
      actorUid: intake.createdBy,
      actorRole: intake.createdByRole,
      detail: {sourceRef: intake.sourceRef, priority: intake.priority},
    }, nowMs);
    if (intake.createdBy !== "system") {
      appendAuditEvent(tx, db, {
        actorAdminId: intake.createdBy,
        actorRole: intake.createdByRole ?? null,
        action: "CASE_CREATED",
        targetType: "case",
        targetId: caseId,
        caseId,
        requestId: intake.requestId ?? null,
        metadata: {type: intake.type, priority: intake.priority, sourceRef: intake.sourceRef},
      }, nowMs);
    }
    return {caseId, created: true, attached: false};
  });
}

// ---------------------------------------------------------------------------
// Workflow commands
// ---------------------------------------------------------------------------

async function readCaseForUpdate(tx: Transaction, db: Firestore, caseId: string): Promise<CaseDoc> {
  const snap = await tx.get(caseRef(db, caseId));
  const doc = parseCaseDoc(caseId, snap.data());
  if (!doc) {
    throw new AdminError("not_found", "case");
  }
  return doc;
}

/**
 * The actor may act on a case they hold, or on an unheld one. Acting on a case
 * a colleague holds needs case.reassign.
 */
function assertMayWork(actor: AdminActor, doc: CaseDoc): void {
  if (doc.assignedTo && doc.assignedTo !== actor.uid && !actor.permissions.has("case.reassign")) {
    throw new AdminError("case_already_assigned", "case_already_assigned", {assignedTo: doc.assignedTo});
  }
}

export async function assignCase(
  db: Firestore,
  actor: AdminActor,
  input: {caseId: string; assigneeUid: string | null; unassign: boolean},
  ctx: {requestId: string; nowMs: number},
): Promise<{caseId: string; assignedTo: string | null; status: CaseStatus; changed: boolean}> {
  const target = input.unassign ? null : (input.assigneeUid ?? actor.uid);
  let assigneeSnap: DocumentSnapshot | null = null;
  if (target && target !== actor.uid) {
    requirePermission(actor, "case.reassign");
    assigneeSnap = await db.doc(`${STAFF_COLLECTION}/${target}`).get();
    const staff = parseStaffRecord(target, assigneeSnap.data());
    if (!staff || staff.status !== "active") {
      throw new AdminError("invalid_argument", "assignee");
    }
  }
  return db.runTransaction(async (tx) => {
    const doc = await readCaseForUpdate(tx, db, input.caseId);
    if (isTerminalCaseStatus(doc.status)) {
      throw new AdminError("invalid_state_transition", "invalid_state_transition", {from: doc.status});
    }
    if (doc.assignedTo === target) {
      // Claiming a case you already hold is a no-op, not an error: a
      // double-click must not fail.
      return {caseId: doc.caseId, assignedTo: target, status: doc.status, changed: false};
    }
    if (doc.assignedTo && !actor.permissions.has("case.reassign")) {
      // Deterministic loser of a claim race.
      throw new AdminError("case_already_assigned", "case_already_assigned", {assignedTo: doc.assignedTo});
    }
    const nextStatus: CaseStatus = target
      ? (doc.status === "open" ? "assigned" : doc.status)
      : "open";
    if (nextStatus !== doc.status) {
      assertTransition(doc.status, nextStatus);
    }
    tx.set(caseRef(db, doc.caseId), {
      assignedTo: target,
      assignedAt: target ? FieldValue.serverTimestamp() : null,
      status: nextStatus,
      updatedAt: FieldValue.serverTimestamp(),
      lastActivityAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendCaseEvent(tx, db, doc.caseId, {
      kind: target ? "assigned" : "unassigned",
      actorUid: actor.uid,
      actorRole: actor.role,
      detail: {from: doc.assignedTo, to: target},
    }, ctx.nowMs);
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: target ? "CASE_ASSIGNED" : "CASE_UNASSIGNED",
      targetType: "case",
      targetId: doc.caseId,
      caseId: doc.caseId,
      requestId: ctx.requestId,
      metadata: {from: doc.assignedTo, to: target},
    }, ctx.nowMs);
    return {caseId: doc.caseId, assignedTo: target, status: nextStatus, changed: true};
  });
}

/** Moves a held case between the working states (in_review / waiting / open). */
export async function setCaseWorkingStatus(
  db: Firestore,
  actor: AdminActor,
  input: {caseId: string; status: "in_review" | "waiting" | "open"},
  ctx: {requestId: string; nowMs: number},
): Promise<{caseId: string; status: CaseStatus}> {
  return db.runTransaction(async (tx) => {
    const doc = await readCaseForUpdate(tx, db, input.caseId);
    assertMayWork(actor, doc);
    if (doc.status === input.status) {
      return {caseId: doc.caseId, status: doc.status};
    }
    assertTransition(doc.status, input.status);
    tx.set(caseRef(db, doc.caseId), {
      status: input.status,
      // Taking a case into review claims it.
      ...(input.status === "in_review" && !doc.assignedTo
        ? {assignedTo: actor.uid, assignedAt: FieldValue.serverTimestamp()}
        : {}),
      ...(input.status === "open" ? {assignedTo: null, assignedAt: null} : {}),
      updatedAt: FieldValue.serverTimestamp(),
      lastActivityAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendCaseEvent(tx, db, doc.caseId, {
      kind: "status_changed",
      actorUid: actor.uid,
      actorRole: actor.role,
      detail: {from: doc.status, to: input.status},
    }, ctx.nowMs);
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "CASE_STATUS_CHANGED",
      targetType: "case",
      targetId: doc.caseId,
      caseId: doc.caseId,
      requestId: ctx.requestId,
      metadata: {from: doc.status, to: input.status},
    }, ctx.nowMs);
    return {caseId: doc.caseId, status: input.status};
  });
}

/** Source records a case resolution closes along with it. */
function reportIdsOf(doc: CaseDoc): string[] {
  return doc.sourceRefs
    .filter((ref) => ref.startsWith("reports/"))
    .map((ref) => ref.slice("reports/".length))
    .filter((id) => /^[A-Za-z0-9_-]{1,128}$/.test(id));
}

export async function resolveCase(
  db: Firestore,
  actor: AdminActor,
  input: {
    caseId: string;
    outcome: "resolved" | "dismissed";
    code: ResolutionCode;
    note: string | null;
  },
  ctx: {requestId: string; nowMs: number},
): Promise<{caseId: string; status: CaseStatus; alreadyResolved: boolean; reportsClosed: number}> {
  return db.runTransaction(async (tx) => {
    const doc = await readCaseForUpdate(tx, db, input.caseId);
    if (isTerminalCaseStatus(doc.status)) {
      // Idempotent replay of the same decision; a different one is refused.
      if (doc.status === input.outcome && doc.resolution?.code === input.code) {
        return {caseId: doc.caseId, status: doc.status, alreadyResolved: true, reportsClosed: 0};
      }
      throw new AdminError("invalid_state_transition", "invalid_state_transition", {from: doc.status, to: input.outcome});
    }
    assertMayWork(actor, doc);
    assertTransition(doc.status, input.outcome);

    const reportRefs = reportIdsOf(doc).map((id) => db.doc(`reports/${id}`));
    const reportSnaps = reportRefs.length ? await Promise.all(reportRefs.map((ref) => tx.get(ref))) : [];
    const keyRef = db.doc(`${CASE_KEY_COLLECTION}/${caseKeyId(doc.correlationKey)}`);
    const keySnap = doc.correlationKey ? await tx.get(keyRef) : null;

    tx.set(caseRef(db, doc.caseId), {
      status: input.outcome,
      assignedTo: doc.assignedTo ?? actor.uid,
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy: actor.uid,
      resolution: {outcome: input.outcome, code: input.code},
      updatedAt: FieldValue.serverTimestamp(),
      lastActivityAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    let reportsClosed = 0;
    for (const snap of reportSnaps) {
      // Only close reports that still exist and are open. set(merge) on a
      // report deleted with its author's account would resurrect a stub.
      if (!snap.exists || snap.data()?.status !== "open") {
        continue;
      }
      tx.set(snap.ref, {
        status: input.outcome,
        resolution: input.code,
        resolvedAt: FieldValue.serverTimestamp(),
        resolvedBy: actor.uid,
        caseId: doc.caseId,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      reportsClosed += 1;
    }
    // Release the correlation key so the next intake opens a fresh case.
    if (keySnap?.exists && keySnap.data()?.caseId === doc.caseId) {
      tx.delete(keyRef);
    }
    if (input.note) {
      const noteId = newNoteId(ctx.nowMs);
      tx.create(db.doc(`${CASE_COLLECTION}/${doc.caseId}/notes/${noteId}`), {
        noteId,
        type: "internal_note",
        authorUid: actor.uid,
        authorRole: actor.role,
        text: input.note,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    appendCaseEvent(tx, db, doc.caseId, {
      kind: input.outcome,
      actorUid: actor.uid,
      actorRole: actor.role,
      detail: {code: input.code, reportsClosed},
    }, ctx.nowMs);
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "CASE_RESOLVED",
      targetType: "case",
      targetId: doc.caseId,
      caseId: doc.caseId,
      requestId: ctx.requestId,
      metadata: {
        outcome: input.outcome,
        code: input.code,
        type: doc.type,
        subjectUserId: doc.subjectUserId,
        reportsClosed,
        internalNote: input.note ?? "",
      },
    }, ctx.nowMs);
    return {caseId: doc.caseId, status: input.outcome, alreadyResolved: false, reportsClosed};
  });
}

export async function escalateCase(
  db: Firestore,
  actor: AdminActor,
  input: {caseId: string; reason: string; note: string | null},
  ctx: {requestId: string; nowMs: number},
): Promise<{caseId: string; priority: Priority; escalationLevel: number}> {
  return db.runTransaction(async (tx) => {
    const doc = await readCaseForUpdate(tx, db, input.caseId);
    if (isTerminalCaseStatus(doc.status)) {
      throw new AdminError("invalid_state_transition", "invalid_state_transition", {from: doc.status});
    }
    const priority = bumpPriority(doc.priority, "high");
    const escalationLevel = doc.escalationLevel + 1;
    // Escalation hands the case back to the queue so a senior can pick it up.
    tx.set(caseRef(db, doc.caseId), {
      escalated: true,
      escalationLevel,
      escalatedAt: FieldValue.serverTimestamp(),
      escalatedBy: actor.uid,
      escalationReason: input.reason,
      priority,
      priorityRank: PRIORITY_RANK[priority],
      status: "open",
      assignedTo: null,
      assignedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
      lastActivityAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (input.note) {
      const noteId = newNoteId(ctx.nowMs);
      tx.create(db.doc(`${CASE_COLLECTION}/${doc.caseId}/notes/${noteId}`), {
        noteId,
        type: "internal_note",
        authorUid: actor.uid,
        authorRole: actor.role,
        text: input.note,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    appendCaseEvent(tx, db, doc.caseId, {
      kind: "escalated",
      actorUid: actor.uid,
      actorRole: actor.role,
      detail: {reason: input.reason, priority, escalationLevel},
    }, ctx.nowMs);
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "CASE_ESCALATED",
      targetType: "case",
      targetId: doc.caseId,
      caseId: doc.caseId,
      requestId: ctx.requestId,
      metadata: {reason: input.reason, priority, escalationLevel},
    }, ctx.nowMs);
    return {caseId: doc.caseId, priority, escalationLevel};
  });
}

export async function addCaseNote(
  db: Firestore,
  actor: AdminActor,
  input: {caseId: string; text: string},
  ctx: {requestId: string; nowMs: number},
): Promise<{caseId: string; noteId: string}> {
  return db.runTransaction(async (tx) => {
    const doc = await readCaseForUpdate(tx, db, input.caseId);
    const noteId = newNoteId(ctx.nowMs);
    tx.create(db.doc(`${CASE_COLLECTION}/${doc.caseId}/notes/${noteId}`), {
      noteId,
      type: "internal_note",
      authorUid: actor.uid,
      authorRole: actor.role,
      text: input.text,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(caseRef(db, doc.caseId), {
      lastActivityAt: FieldValue.serverTimestamp(),
      noteCount: FieldValue.increment(1),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "CASE_NOTE_ADDED",
      targetType: "case",
      targetId: doc.caseId,
      caseId: doc.caseId,
      requestId: ctx.requestId,
      metadata: {noteId, noteLength: input.text.length},
    }, ctx.nowMs);
    return {caseId: doc.caseId, noteId};
  });
}

/**
 * Reads the case a decision is being linked to, inside the caller's
 * transaction. Must run before that transaction writes anything.
 */
export async function readLinkableCase(
  tx: Transaction,
  db: Firestore,
  caseId: string | null,
): Promise<CaseDoc | null> {
  if (!caseId) {
    return null;
  }
  const doc = await readCaseForUpdate(tx, db, caseId);
  return doc;
}

/** Records a moderation action against a case (inside the caller's transaction). */
export function linkActionToCase(
  tx: Transaction,
  db: Firestore,
  doc: CaseDoc,
  input: {actionId: string; actionType: string; actor: AdminActor},
  nowMs: number,
): void {
  tx.set(caseRef(db, doc.caseId), {
    actionIds: FieldValue.arrayUnion(input.actionId),
    ...(ACTIVE_CASE_STATUSES.includes(doc.status) && !doc.assignedTo
      ? {assignedTo: input.actor.uid, assignedAt: FieldValue.serverTimestamp(), status: doc.status === "open" ? "assigned" : doc.status}
      : {}),
    updatedAt: FieldValue.serverTimestamp(),
    lastActivityAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  appendCaseEvent(tx, db, doc.caseId, {
    kind: "action_taken",
    actorUid: input.actor.uid,
    actorRole: input.actor.role,
    detail: {actionId: input.actionId, actionType: input.actionType},
  }, nowMs);
}
