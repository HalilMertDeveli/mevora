import {randomBytes} from "node:crypto";
import {FieldValue, type DocumentData} from "firebase-admin/firestore";
import {ACTION_COLLECTION, buildActionRecord} from "../actions/actionTypes.js";
import {appendAuditEvent, recordAuditEvent} from "../audit/auditService.js";
import {STAFF_COLLECTION, parseStaffRecord, type AdminActor} from "../auth/adminAuthorization.js";
import {openOrAttachCase} from "../cases/caseService.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, deterministicId, encodeCursor, iso} from "../validation.js";
import {loadUserCards} from "../users/userCards.js";

/**
 * Support operations over the existing `supportTickets` collection.
 *
 * Tickets are created by two writers that must keep working unchanged: the
 * Flutter app (rules-validated, `userId == auth.uid`, lowercase statuses) and
 * the public mevora-support-web (Admin SDK, capitalised statuses, visitor-
 * typed userId). The console reads both shapes, writes canonical lowercase
 * values, and only ever adds server-owned fields.
 *
 * Conversation:
 *   supportTickets/{id}/messages/{messageId}       user-visible thread
 *   supportTickets/{id}/internalNotes/{noteId}     staff only, never shown
 * A reply and an internal note are different commands writing different
 * collections, so a note cannot leak into the thread by a wrong flag.
 * Thread messages carry no staff uid — the member sees "Mevora Support".
 */

export const TICKET_STATUSES = ["open", "in_progress", "resolved", "closed"] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];
export const TICKET_PRIORITIES = ["low", "normal", "high", "urgent"] as const;
export type TicketPriority = (typeof TICKET_PRIORITIES)[number];

const STATUS_VARIANTS: Record<TicketStatus, string[]> = {
  open: ["open", "Open"],
  in_progress: ["in_progress", "InProgress"],
  resolved: ["resolved", "Resolved"],
  closed: ["closed", "Closed"],
};

export function normalizeTicketStatus(raw: unknown): TicketStatus {
  const value = String(raw ?? "open");
  for (const [canonical, variants] of Object.entries(STATUS_VARIANTS)) {
    if (variants.includes(value)) {
      return canonical as TicketStatus;
    }
  }
  return "open";
}

export function normalizeTicketPriority(raw: unknown): TicketPriority {
  const value = String(raw ?? "normal").toLowerCase();
  return (TICKET_PRIORITIES as readonly string[]).includes(value) ? (value as TicketPriority) : "normal";
}

/**
 * Only tickets created in the app bind `userId` to the signed-in member (the
 * rules enforce it). A website ticket's userId is whatever the visitor typed,
 * so the console flags it rather than treating it as that member's ticket.
 */
export function ticketUserVerified(data: DocumentData): boolean {
  return data.source !== "website" && typeof data.userId === "string" && !data.userId.startsWith("web-");
}

function ticketRow(id: string, data: DocumentData) {
  return {
    ticketId: id,
    subject: typeof data.subject === "string" ? data.subject.slice(0, 200) : null,
    category: data.category ?? null,
    status: normalizeTicketStatus(data.status),
    priority: normalizeTicketPriority(data.priority),
    source: data.source === "website" ? "website" : "app",
    userId: data.userId ?? null,
    userIdVerified: ticketUserVerified(data),
    assignedTo: data.assignedTo ?? null,
    createdAt: iso(data.createdAt),
    updatedAt: iso(data.updatedAt),
    firstResponseAt: iso(data.firstResponseAt),
    lastSupportReplyAt: iso(data.lastSupportReplyAt),
    escalated: Boolean(data.escalatedAt),
    caseId: data.caseId ?? null,
  };
}

export async function listSupportTickets(
  deps: AdminDeps,
  actor: AdminActor,
  input: {status: TicketStatus | "active" | "all"; assigned: "me" | "any"; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q = db.collection("supportTickets") as FirebaseFirestore.Query;
  if (input.assigned === "me") {
    q = q.where("assignedTo", "==", actor.uid);
  }
  if (input.status === "active") {
    q = q.where("status", "in", [...STATUS_VARIANTS.open, ...STATUS_VARIANTS.in_progress]);
  } else if (input.status !== "all") {
    q = q.where("status", "in", STATUS_VARIANTS[input.status]);
  }
  q = q.orderBy("createdAt", "desc").orderBy("__name__", "desc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const rows = snap.docs.map((doc) => ticketRow(doc.id, doc.data()));
  const cards = await loadUserCards(db, rows.filter((r) => r.userIdVerified).map((r) => r.userId), deps.now());
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: rows.map((row) => ({...row, user: row.userIdVerified && row.userId ? cards.get(row.userId) ?? null : null})),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("createdAt")), last.id])
      : null,
  };
}

export async function getSupportTicket(deps: AdminDeps, ticketId: string) {
  const {db} = deps;
  const ref = db.doc(`supportTickets/${ticketId}`);
  const [ticket, messages, notes] = await Promise.all([
    ref.get(),
    ref.collection("messages").orderBy("createdAt", "asc").limit(100).get(),
    ref.collection("internalNotes").orderBy("createdAt", "asc").limit(100).get(),
  ]);
  if (!ticket.exists) {
    throw new AdminError("not_found", "ticket");
  }
  const data = ticket.data() ?? {};
  const row = ticketRow(ticket.id, data);
  const cards = await loadUserCards(db, row.userIdVerified ? [row.userId] : [], deps.now());
  const staffIds = [...new Set(notes.docs.map((n) => String(n.get("authorUid") ?? "")).filter(Boolean))];
  const staffDocs = staffIds.length ? await db.getAll(...staffIds.map((u) => db.doc(`${STAFF_COLLECTION}/${u}`))) : [];
  const staffNames = new Map(staffDocs.map((s) => [s.id, parseStaffRecord(s.id, s.data())?.displayName ?? null]));
  const attachments = Array.isArray(data.attachments)
    ? (data.attachments as unknown[]).filter((a): a is string => typeof a === "string").slice(0, 3)
    : [];
  return {
    ...row,
    // Contact details the member supplied on the ticket itself; support
    // needs them to answer a website ticket, which has no in-app thread.
    contactName: typeof data.name === "string" ? data.name.slice(0, 120) : null,
    contactEmail: typeof data.email === "string" ? data.email : null,
    message: typeof data.message === "string" ? data.message.slice(0, 4000) : (typeof data.description === "string" ? data.description.slice(0, 4000) : null),
    attachmentCount: attachments.length,
    resolvedAt: iso(data.resolvedAt),
    resolvedBy: data.resolvedBy ?? null,
    user: row.userIdVerified && row.userId ? cards.get(row.userId) ?? null : null,
    thread: messages.docs.map((m) => ({
      messageId: m.id,
      type: m.get("type") ?? "support",
      text: typeof m.get("text") === "string" ? String(m.get("text")) : "",
      createdAt: iso(m.get("createdAt")),
    })),
    internalNotes: notes.docs.map((n) => ({
      noteId: n.id,
      authorUid: n.get("authorUid") ?? null,
      authorName: staffNames.get(String(n.get("authorUid") ?? "")) ?? null,
      text: typeof n.get("text") === "string" ? String(n.get("text")) : "",
      createdAt: iso(n.get("createdAt")),
    })),
  };
}

/** Image bytes of one ticket attachment, path-checked against the ticket. */
export async function getSupportAttachment(deps: AdminDeps, input: {ticketId: string; index: number}) {
  const snap = await deps.db.doc(`supportTickets/${input.ticketId}`).get();
  if (!snap.exists) {
    throw new AdminError("not_found", "ticket");
  }
  const attachments = Array.isArray(snap.get("attachments")) ? (snap.get("attachments") as unknown[]) : [];
  const path = attachments[input.index];
  if (typeof path !== "string") {
    throw new AdminError("not_found", "attachment");
  }
  const userId = String(snap.get("userId") ?? "");
  const allowed = path.startsWith(`support/${input.ticketId}/`) ||
    (userId.length > 0 && path.startsWith(`users/${userId}/support/${input.ticketId}/`));
  if (!allowed || path.includes("..")) {
    throw new AdminError("not_found", "attachment");
  }
  const file = deps.bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) {
    throw new AdminError("not_found", "attachment");
  }
  const [metadata] = await file.getMetadata();
  const contentType = String(metadata.contentType ?? "");
  if (!/^image\/(jpeg|jpg|png|webp)$/i.test(contentType) || Number(metadata.size ?? 0) > 5 * 1024 * 1024) {
    throw new AdminError("invalid_state_transition", "unsupported_attachment");
  }
  const [buffer] = await file.download({validation: false});
  return {contentType, dataBase64: buffer.toString("base64")};
}

async function readTicket(tx: FirebaseFirestore.Transaction, deps: AdminDeps, ticketId: string) {
  const snap = await tx.get(deps.db.doc(`supportTickets/${ticketId}`));
  if (!snap.exists) {
    throw new AdminError("not_found", "ticket");
  }
  return snap;
}

export async function assignSupportTicket(
  deps: AdminDeps,
  actor: AdminActor,
  input: {ticketId: string; assigneeUid: string | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const target = input.assigneeUid ?? actor.uid;
  if (target !== actor.uid) {
    const staff = parseStaffRecord(target, (await db.doc(`${STAFF_COLLECTION}/${target}`).get()).data());
    if (!staff || staff.status !== "active") {
      throw new AdminError("invalid_argument", "assignee");
    }
  }
  return db.runTransaction(async (tx) => {
    const snap = await readTicket(tx, deps, input.ticketId);
    const status = normalizeTicketStatus(snap.get("status"));
    if (status === "closed") {
      throw new AdminError("ticket_closed");
    }
    if (snap.get("assignedTo") === target) {
      return {ticketId: input.ticketId, assignedTo: target, changed: false};
    }
    tx.set(snap.ref, {
      assignedTo: target,
      assignedAt: FieldValue.serverTimestamp(),
      status: status === "open" ? "in_progress" : status,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "SUPPORT_ASSIGNED",
      targetType: "support_ticket",
      targetId: input.ticketId,
      requestId,
      metadata: {from: snap.get("assignedTo") ?? null, to: target},
    }, nowMs);
    return {ticketId: input.ticketId, assignedTo: target, changed: true};
  });
}

export async function replySupportTicket(
  deps: AdminDeps,
  actor: AdminActor,
  input: {ticketId: string; text: string; idempotencyKey: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const messageId = deterministicId("msg", actor.uid, input.ticketId, input.idempotencyKey);
  const ticketRef = db.doc(`supportTickets/${input.ticketId}`);
  const messageRef = ticketRef.collection("messages").doc(messageId);
  return db.runTransaction(async (tx) => {
    const [snap, existing] = await Promise.all([readTicket(tx, deps, input.ticketId), tx.get(messageRef)]);
    if (existing.exists) {
      return {ticketId: input.ticketId, messageId, replayed: true};
    }
    const status = normalizeTicketStatus(snap.get("status"));
    if (status === "closed") {
      throw new AdminError("ticket_closed");
    }
    tx.create(messageRef, {
      messageId,
      type: "support",
      // Read by the ticket owner (rules): who in support answered is not
      // theirs to know; the audit log keeps that.
      visibility: "user",
      authorLabel: "Mevora Support",
      text: input.text,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(ticketRef, {
      status: "in_progress",
      ...(snap.get("firstResponseAt") ? {} : {firstResponseAt: FieldValue.serverTimestamp()}),
      lastSupportReplyAt: FieldValue.serverTimestamp(),
      supportReplyCount: FieldValue.increment(1),
      hasUnreadSupportReply: true,
      ...(snap.get("assignedTo") ? {} : {assignedTo: actor.uid, assignedAt: FieldValue.serverTimestamp()}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "SUPPORT_REPLIED",
      targetType: "support_ticket",
      targetId: input.ticketId,
      requestId,
      metadata: {messageId, replyLength: input.text.length},
    }, nowMs);
    return {ticketId: input.ticketId, messageId, replayed: false};
  });
}

export async function addSupportNote(
  deps: AdminDeps,
  actor: AdminActor,
  input: {ticketId: string; text: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const noteId = `note_${nowMs.toString(36)}_${randomBytes(5).toString("hex")}`;
  const ticketRef = db.doc(`supportTickets/${input.ticketId}`);
  return db.runTransaction(async (tx) => {
    await readTicket(tx, deps, input.ticketId);
    tx.create(ticketRef.collection("internalNotes").doc(noteId), {
      noteId,
      authorUid: actor.uid,
      authorRole: actor.role,
      text: input.text,
      createdAt: FieldValue.serverTimestamp(),
    });
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "SUPPORT_NOTE_ADDED",
      targetType: "support_ticket",
      targetId: input.ticketId,
      requestId,
      metadata: {noteId, noteLength: input.text.length},
    }, nowMs);
    return {ticketId: input.ticketId, noteId};
  });
}

export async function updateSupportTicket(
  deps: AdminDeps,
  actor: AdminActor,
  input: {ticketId: string; status: "in_progress" | "open" | null; priority: TicketPriority | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  return db.runTransaction(async (tx) => {
    const snap = await readTicket(tx, deps, input.ticketId);
    const current = normalizeTicketStatus(snap.get("status"));
    if (current === "closed") {
      throw new AdminError("ticket_closed");
    }
    const patch: Record<string, unknown> = {updatedAt: FieldValue.serverTimestamp()};
    if (input.status) {
      patch.status = input.status;
    }
    if (input.priority) {
      patch.priority = input.priority;
    }
    tx.set(snap.ref, patch, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "SUPPORT_STATUS_CHANGED",
      targetType: "support_ticket",
      targetId: input.ticketId,
      requestId,
      metadata: {from: current, status: input.status, priority: input.priority},
    }, nowMs);
    return {ticketId: input.ticketId, status: input.status ?? current, priority: input.priority ?? normalizeTicketPriority(snap.get("priority"))};
  });
}

export async function resolveSupportTicket(
  deps: AdminDeps,
  actor: AdminActor,
  input: {ticketId: string; outcome: "resolved" | "closed"; resolutionNote: string | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  return db.runTransaction(async (tx) => {
    const snap = await readTicket(tx, deps, input.ticketId);
    const current = normalizeTicketStatus(snap.get("status"));
    if (current === input.outcome) {
      return {ticketId: input.ticketId, status: current, replayed: true};
    }
    if (current === "closed") {
      throw new AdminError("ticket_closed");
    }
    tx.set(snap.ref, {
      status: input.outcome,
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy: actor.uid,
      ...(snap.get("assignedTo") ? {} : {assignedTo: actor.uid}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (input.resolutionNote) {
      const noteId = `note_${nowMs.toString(36)}_${randomBytes(5).toString("hex")}`;
      tx.create(snap.ref.collection("internalNotes").doc(noteId), {
        noteId,
        authorUid: actor.uid,
        authorRole: actor.role,
        text: input.resolutionNote,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "SUPPORT_RESOLVED",
      targetType: "support_ticket",
      targetId: input.ticketId,
      requestId,
      metadata: {from: current, outcome: input.outcome, internalNote: input.resolutionNote ?? ""},
    }, nowMs);
    return {ticketId: input.ticketId, status: input.outcome, replayed: false};
  });
}

/**
 * Hands a ticket to Trust & Safety: opens (or joins) a SUPPORT_ESCALATION
 * case and, when the ticket belongs to a real member, records the escalation
 * as a moderation action on that member.
 */
export async function escalateSupportTicket(
  deps: AdminDeps,
  actor: AdminActor,
  input: {ticketId: string; reason: string; priority: "normal" | "medium" | "high" | "critical"; idempotencyKey: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const snap = await db.doc(`supportTickets/${input.ticketId}`).get();
  if (!snap.exists) {
    throw new AdminError("not_found", "ticket");
  }
  const data = snap.data() ?? {};
  const verifiedUser = ticketUserVerified(data) ? String(data.userId) : null;
  const {caseId} = await openOrAttachCase(db, {
    type: "SUPPORT_ESCALATION",
    correlationKey: `support:${input.ticketId}`,
    subjectUserId: verifiedUser,
    sourceRef: `supportTickets/${input.ticketId}`,
    reasonCode: input.reason,
    priority: input.priority,
    summary: `Support escalation: ${String(data.category ?? "general")}`,
    createdBy: actor.uid,
    createdByRole: actor.role,
    requestId,
  }, nowMs);
  const actionId = deterministicId("act", actor.uid, "support_escalation", input.ticketId, input.idempotencyKey);
  await db.runTransaction(async (tx) => {
    const actionRef = db.doc(`${ACTION_COLLECTION}/${actionId}`);
    const existing = await tx.get(actionRef);
    if (existing.exists) {
      return;
    }
    tx.set(snap.ref, {escalatedAt: FieldValue.serverTimestamp(), caseId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (verifiedUser) {
      tx.create(actionRef, buildActionRecord({
        actionId,
        type: "SUPPORT_ESCALATION",
        targetUserId: verifiedUser,
        caseId,
        reasonCode: input.reason,
        internalNote: null,
        actorAdminId: actor.uid,
        actorRole: actor.role,
        requestId,
        idempotencyKey: input.idempotencyKey,
        effectiveAtMs: nowMs,
        subject: {ticketId: input.ticketId},
      }));
    }
  });
  await recordAuditEvent(db, {
    actorAdminId: actor.uid,
    actorRole: actor.role,
    action: "SUPPORT_ESCALATED",
    targetType: "support_ticket",
    targetId: input.ticketId,
    caseId,
    actionId: verifiedUser ? actionId : null,
    requestId,
    metadata: {reason: input.reason, priority: input.priority, userVerified: Boolean(verifiedUser)},
  }, nowMs);
  return {ticketId: input.ticketId, caseId, actionId: verifiedUser ? actionId : null};
}
