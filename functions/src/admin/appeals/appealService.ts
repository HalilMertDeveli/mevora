import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {effectiveAccountStatus} from "../../profileSafety.js";
import {
  ACTION_COLLECTION,
  APPEALABLE_ACTION_TYPES,
  buildActionRecord,
  type ActionType,
} from "../actions/actionTypes.js";
import {appendAuditEvent, recordAuditEvent} from "../audit/auditService.js";
import {requirePermission, type AdminActor} from "../auth/adminAuthorization.js";
import {openOrAttachCase, resolveCase} from "../cases/caseService.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {applyAccountAction} from "../users/accountActions.js";
import {cursorPart, decodeCursor, deterministicId, encodeCursor, iso, toMillis} from "../validation.js";
import {loadUserCards} from "../users/userCards.js";

/**
 * Appeals: `appeals/{appealId}`, one per moderation action.
 *
 * A member appeals a decision made about them. The appeal id is derived from
 * the action id, so a second submission for the same action is the same
 * appeal, not a new one. Deciding an appeal never edits or deletes the
 * decision it is about:
 *
 *   rejected  → APPEAL_REJECTED action, the original stands
 *   accepted  → APPEAL_ACCEPTED action, and for a suspension or ban that is
 *               still in force, a RESTORE_ACCOUNT action through the normal
 *               account path. An accepted appeal against a re-verification
 *               request does NOT make the member verified — only the
 *               provider can; it only records that the request was
 *               overturned.
 *
 * The reviewer must not be the moderator who took the original decision
 * (super admins excepted), so no one marks their own work.
 */
export const APPEAL_COLLECTION = "appeals";
export const APPEAL_WINDOW_DAYS = 30;
export const APPEAL_STATUSES = ["open", "in_review", "resolved"] as const;
export type AppealStatus = (typeof APPEAL_STATUSES)[number];

export function appealIdFor(actionId: string): string {
  return `appeal_${actionId}`;
}

function appealRow(id: string, data: DocumentData) {
  return {
    appealId: id,
    userId: data.userId ?? null,
    moderationActionId: data.moderationActionId ?? null,
    actionType: data.actionType ?? null,
    caseId: data.caseId ?? null,
    reason: typeof data.reason === "string" ? data.reason.slice(0, 2000) : null,
    status: data.status ?? "open",
    decision: data.decision ?? null,
    source: data.source ?? "app",
    sourceTicketId: data.sourceTicketId ?? null,
    assignedTo: data.assignedTo ?? null,
    resolvedBy: data.resolvedBy ?? null,
    resolvedAt: iso(data.resolvedAt),
    resolution: data.resolution ?? null,
    createdAt: iso(data.createdAt),
  };
}

/**
 * Opens an appeal. Used by the member's own callable and by staff filing a
 * ban appeal that arrived as a support ticket (a banned account cannot sign
 * in to appeal itself).
 */
export async function openAppeal(
  db: Firestore,
  input: {
    userId: string;
    moderationActionId: string;
    reason: string;
    source: "app" | "support_ticket";
    sourceTicketId: string | null;
    openedBy: string;
    openedByRole: string | null;
    requestId: string | null;
  },
  nowMs: number,
): Promise<{appealId: string; created: boolean; caseId: string | null}> {
  const actionSnap = await db.doc(`${ACTION_COLLECTION}/${input.moderationActionId}`).get();
  if (!actionSnap.exists || actionSnap.get("targetUserId") !== input.userId) {
    // Same answer for "no such action" and "not yours": no oracle.
    throw new AdminError("appeal_not_allowed");
  }
  const type = String(actionSnap.get("type")) as ActionType;
  if (!APPEALABLE_ACTION_TYPES.includes(type)) {
    throw new AdminError("appeal_not_allowed");
  }
  if (actionSnap.get("overturnedByActionId")) {
    throw new AdminError("appeal_not_allowed", "already_overturned");
  }
  const effectiveMs = toMillis(actionSnap.get("effectiveAt")) ?? toMillis(actionSnap.get("createdAt")) ?? nowMs;
  if (nowMs - effectiveMs > APPEAL_WINDOW_DAYS * 24 * 60 * 60 * 1000) {
    throw new AdminError("appeal_window_closed");
  }
  const appealId = appealIdFor(input.moderationActionId);
  const ref = db.doc(`${APPEAL_COLLECTION}/${appealId}`);
  const created = await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      return false;
    }
    tx.create(ref, {
      appealId,
      userId: input.userId,
      moderationActionId: input.moderationActionId,
      actionType: type,
      originalActorAdminId: actionSnap.get("actorAdminId") ?? null,
      caseId: null,
      reason: input.reason,
      status: "open" satisfies AppealStatus,
      decision: null,
      source: input.source,
      sourceTicketId: input.sourceTicketId,
      assignedTo: null,
      resolvedBy: null,
      resolvedAt: null,
      resolution: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(actionSnap.ref, {appealId}, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: input.openedBy,
      actorRole: input.openedByRole,
      action: input.source === "app" ? "APPEAL_SUBMITTED" : "APPEAL_OPENED_BY_STAFF",
      targetType: "appeal",
      targetId: appealId,
      actionId: input.moderationActionId,
      requestId: input.requestId,
      metadata: {userId: input.userId, actionType: type, reason: input.reason},
    }, nowMs);
    return true;
  });
  if (!created) {
    const existing = await ref.get();
    return {appealId, created: false, caseId: (existing.get("caseId") as string | null) ?? null};
  }
  const {caseId} = await openOrAttachCase(db, {
    type: "APPEAL",
    correlationKey: `appeal:${appealId}`,
    subjectUserId: input.userId,
    sourceRef: `${APPEAL_COLLECTION}/${appealId}`,
    reasonCode: type,
    priority: type === "PERMANENT_BAN" || type === "TEMPORARY_SUSPENSION" ? "high" : "medium",
    summary: `Appeal against ${type}`,
    createdBy: "system",
  }, nowMs);
  await ref.set({caseId}, {merge: true});
  return {appealId, created: true, caseId};
}

export async function listAppeals(
  deps: AdminDeps,
  input: {status: AppealStatus; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q = db.collection(APPEAL_COLLECTION)
    .where("status", "==", input.status)
    .orderBy("createdAt", input.status === "resolved" ? "desc" : "asc")
    .orderBy("__name__", input.status === "resolved" ? "desc" : "asc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const rows = snap.docs.map((doc) => appealRow(doc.id, doc.data()));
  const cards = await loadUserCards(db, rows.map((r) => r.userId), deps.now());
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: rows.map((row) => ({...row, user: row.userId ? cards.get(row.userId) ?? null : null})),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("createdAt")), last.id])
      : null,
  };
}

export async function getAppeal(deps: AdminDeps, appealId: string) {
  const {db} = deps;
  const snap = await db.doc(`${APPEAL_COLLECTION}/${appealId}`).get();
  if (!snap.exists) {
    throw new AdminError("not_found", "appeal");
  }
  const row = appealRow(snap.id, snap.data() ?? {});
  const action = row.moderationActionId
    ? await db.doc(`${ACTION_COLLECTION}/${row.moderationActionId}`).get()
    : null;
  const cards = await loadUserCards(db, [row.userId], deps.now());
  const account = row.userId ? await db.doc(`users/${row.userId}`).get() : null;
  return {
    ...row,
    user: row.userId ? cards.get(row.userId) ?? null : null,
    currentAccountStatus: account?.exists ? effectiveAccountStatus(account.data(), deps.now()) : null,
    originalAction: action?.exists
      ? {
        actionId: action.id,
        type: action.get("type") ?? null,
        reasonCode: action.get("reasonCode") ?? null,
        internalNote: action.get("internalNote") ?? null,
        actorAdminId: action.get("actorAdminId") ?? null,
        createdAt: iso(action.get("createdAt") ?? action.get("effectiveAt")),
        expiresAt: iso(action.get("expiresAt")),
        overturnedByActionId: action.get("overturnedByActionId") ?? null,
      }
      : null,
  };
}

export async function assignAppeal(
  deps: AdminDeps,
  actor: AdminActor,
  input: {appealId: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const ref = db.doc(`${APPEAL_COLLECTION}/${input.appealId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new AdminError("not_found", "appeal");
    }
    if (snap.get("status") === "resolved") {
      throw new AdminError("appeal_already_resolved");
    }
    const holder = snap.get("assignedTo");
    if (holder === actor.uid) {
      return {appealId: input.appealId, assignedTo: actor.uid, changed: false};
    }
    if (holder && !actor.permissions.has("case.reassign")) {
      throw new AdminError("case_already_assigned", "case_already_assigned", {assignedTo: holder});
    }
    tx.set(ref, {
      assignedTo: actor.uid,
      status: "in_review" satisfies AppealStatus,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "APPEAL_ASSIGNED",
      targetType: "appeal",
      targetId: input.appealId,
      requestId,
      metadata: {from: holder ?? null},
    }, nowMs);
    return {appealId: input.appealId, assignedTo: actor.uid, changed: true};
  });
}

export async function resolveAppeal(
  deps: AdminDeps,
  actor: AdminActor,
  input: {
    appealId: string;
    decision: "accept" | "reject";
    userMessage: string;
    internalNote: string | null;
    idempotencyKey: string;
  },
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  if (input.decision === "accept") {
    // Accepting may have to lift a suspension or ban; check up front so an
    // appeal is never marked accepted by someone who cannot carry it out.
    requirePermission(actor, "user.restore");
  }
  const ref = db.doc(`${APPEAL_COLLECTION}/${input.appealId}`);
  const decisionActionId = deterministicId("act", actor.uid, "appeal", input.appealId, input.idempotencyKey);
  const decisionRef = db.doc(`${ACTION_COLLECTION}/${decisionActionId}`);

  const first = await db.runTransaction(async (tx) => {
    const [snap, decisionSnap] = await Promise.all([tx.get(ref), tx.get(decisionRef)]);
    if (!snap.exists) {
      throw new AdminError("not_found", "appeal");
    }
    if (decisionSnap.exists) {
      return {replay: true as const, data: snap.data() ?? {}};
    }
    if (snap.get("status") === "resolved") {
      throw new AdminError("appeal_already_resolved");
    }
    const holder = snap.get("assignedTo");
    if (holder && holder !== actor.uid && !actor.permissions.has("case.reassign")) {
      throw new AdminError("case_already_assigned", "case_already_assigned", {assignedTo: holder});
    }
    if (snap.get("originalActorAdminId") === actor.uid && actor.role !== "super_admin") {
      throw new AdminError("appeal_self_review");
    }
    const originalRef = db.doc(`${ACTION_COLLECTION}/${String(snap.get("moderationActionId"))}`);
    const [original, account] = await Promise.all([
      tx.get(originalRef),
      tx.get(db.doc(`users/${String(snap.get("userId"))}`)),
    ]);
    const accepted = input.decision === "accept";
    const type: ActionType = accepted ? "APPEAL_ACCEPTED" : "APPEAL_REJECTED";
    tx.create(decisionRef, buildActionRecord({
      actionId: decisionActionId,
      type,
      targetUserId: String(snap.get("userId")),
      caseId: (snap.get("caseId") as string | null) ?? null,
      reasonCode: accepted ? "APPEAL_ACCEPTED" : "APPEAL_REJECTED",
      internalNote: input.internalNote,
      userMessage: input.userMessage,
      actorAdminId: actor.uid,
      actorRole: actor.role,
      requestId,
      idempotencyKey: input.idempotencyKey,
      effectiveAtMs: nowMs,
      relatedActionId: original.id,
      subject: {appealId: input.appealId},
    }));
    tx.set(ref, {
      status: "resolved" satisfies AppealStatus,
      decision: accepted ? "accepted" : "rejected",
      assignedTo: holder ?? actor.uid,
      resolvedBy: actor.uid,
      resolvedAt: FieldValue.serverTimestamp(),
      resolution: {decision: accepted ? "accepted" : "rejected", userMessage: input.userMessage, decisionActionId},
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (accepted && original.exists && !original.get("overturnedByActionId")) {
      tx.set(original.ref, {overturnedByActionId: decisionActionId, overturnedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: accepted ? "APPEAL_ACCEPTED" : "APPEAL_REJECTED",
      targetType: "appeal",
      targetId: input.appealId,
      caseId: (snap.get("caseId") as string | null) ?? null,
      actionId: decisionActionId,
      requestId,
      metadata: {
        originalActionId: original.id,
        originalType: original.get("type") ?? null,
        internalNote: input.internalNote ?? "",
      },
    }, nowMs);
    const originalType = String(original.get("type") ?? "");
    // Restore only what is still in force *because of this action*.
    const stillInForce = account.exists &&
      account.get("statusActionId") === original.id &&
      ["suspended", "banned"].includes(effectiveAccountStatus(account.data(), nowMs));
    return {
      replay: false as const,
      data: snap.data() ?? {},
      needsRestore: accepted && ["TEMPORARY_SUSPENSION", "PERMANENT_BAN"].includes(originalType) && stillInForce,
    };
  });

  const appeal = first.data;
  let restoreActionId: string | null = null;
  if (!first.replay && first.needsRestore) {
    // The account path owns account state; an appeal never writes it directly.
    requirePermission(actor, "user.restore");
    const restored = await applyAccountAction(deps, actor, {
      targetUid: String(appeal.userId),
      command: {kind: "restore", reasonCode: "APPEAL_ACCEPTED"},
      internalNote: input.internalNote,
      caseId: (appeal.caseId as string | null) ?? null,
      idempotencyKey: `${input.idempotencyKey}-restore`,
      relatedActionId: String(appeal.moderationActionId),
      appealId: input.appealId,
    }, requestId);
    restoreActionId = restored.actionId;
    await ref.set({resolution: {restoreActionId}}, {merge: true});
  }

  const caseId = typeof appeal.caseId === "string" ? appeal.caseId : null;
  if (!first.replay && caseId) {
    try {
      await resolveCase(db, actor, {
        caseId,
        outcome: "resolved",
        code: input.decision === "accept" ? "action_taken" : "no_violation",
        note: null,
      }, {requestId, nowMs});
    } catch (error) {
      // The appeal decision stands even if its case was already closed.
      if (!(error instanceof AdminError)) {
        throw error;
      }
    }
  }
  return {
    appealId: input.appealId,
    decision: input.decision,
    decisionActionId,
    restoreActionId,
    replayed: first.replay,
  };
}

/** Staff files an appeal on a member's behalf (e.g. from a support ticket). */
export async function openAppealForUser(
  deps: AdminDeps,
  actor: AdminActor,
  input: {userId: string; moderationActionId: string; reason: string; ticketId: string | null},
  requestId: string,
) {
  const result = await openAppeal(deps.db, {
    userId: input.userId,
    moderationActionId: input.moderationActionId,
    reason: input.reason,
    source: "support_ticket",
    sourceTicketId: input.ticketId,
    openedBy: actor.uid,
    openedByRole: actor.role,
    requestId,
  }, deps.now());
  if (!result.created) {
    await recordAuditEvent(deps.db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "APPEAL_OPENED_BY_STAFF",
      targetType: "appeal",
      targetId: result.appealId,
      requestId,
      metadata: {duplicate: true},
    }, deps.now());
  }
  return result;
}
