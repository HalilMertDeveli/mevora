import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {effectiveAccountStatus, type EffectiveAccountStatus} from "../../profileSafety.js";
import {safeLogMeta} from "../../security/logHygiene.js";
import {ACTION_COLLECTION, buildActionRecord, type ActionType} from "../actions/actionTypes.js";
import {appendAuditEvent} from "../audit/auditService.js";
import type {AuditAction} from "../audit/auditTypes.js";
import {STAFF_COLLECTION, parseStaffRecord, type AdminActor} from "../auth/adminAuthorization.js";
import {ROLE_RANK} from "../auth/roles.js";
import {linkActionToCase, readLinkableCase} from "../cases/caseService.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {deterministicId, toMillis} from "../validation.js";

/**
 * Account sanctions: warn, suspend, ban, restore.
 *
 * `users/{uid}.accountStatus` is the canonical state. For the transition
 * period the legacy `isBanned` / `isSuspended` booleans are mirrored on every
 * write, so any reader that has not moved to accountStatus yet sees the same
 * decision (and effectiveAccountStatus honours either).
 *
 * Every command is one transaction that re-reads the account, validates the
 * transition, and writes the account change, the moderationActions record,
 * the audit event and the case link together. Firebase Auth side effects
 * (disabling a banned account, revoking its sessions) cannot join that
 * transaction; they run after it and their outcome is recorded on the action
 * (`authSync`), and replaying the command retries them.
 */

export const MIN_SUSPENSION_HOURS = 1;
export const MAX_SUSPENSION_HOURS = 24 * 365;

export type AccountCommand =
  | {kind: "warn"; reasonCode: string; userMessage: string | null}
  | {kind: "suspend"; reasonCode: string; durationHours: number}
  | {kind: "ban"; reasonCode: string}
  | {kind: "restore"; reasonCode: string};

export interface AccountTransition {
  actionType: ActionType;
  auditAction: AuditAction;
  previousState: Record<string, unknown>;
  newState: Record<string, unknown>;
  userPatch: Record<string, unknown>;
  expiresAtMs: number | null;
  authEffect: "disable" | "enable" | "none";
}

function stateOf(account: DocumentData, nowMs: number): Record<string, unknown> {
  const until = toMillis(account.suspendedUntil);
  return {
    accountStatus: effectiveAccountStatus(account, nowMs),
    storedAccountStatus: String(account.accountStatus ?? "active"),
    suspendedUntil: until ? new Date(until).toISOString() : null,
    statusActionId: typeof account.statusActionId === "string" ? account.statusActionId : null,
  };
}

/**
 * Pure transition planner — the business rules, with no I/O. Throws the
 * domain error a UI can explain.
 */
export function planAccountTransition(
  account: DocumentData,
  command: AccountCommand,
  actionId: string,
  nowMs: number,
): AccountTransition {
  const current: EffectiveAccountStatus = effectiveAccountStatus(account, nowMs);
  const previousState = stateOf(account, nowMs);
  if (current === "deleted") {
    throw new AdminError("user_deleted");
  }
  const statusFields = (status: "active" | "suspended" | "banned", reasonCode: string, until: number | null) => ({
    accountStatus: status,
    isBanned: status === "banned",
    isSuspended: status === "suspended",
    suspendedUntil: until ? new Date(until) : null,
    statusReasonCode: reasonCode,
    statusActionId: actionId,
    statusUpdatedAt: FieldValue.serverTimestamp(),
  });

  switch (command.kind) {
  case "warn": {
    if (current === "banned") {
      throw new AdminError("user_already_banned");
    }
    return {
      actionType: "WARNING",
      auditAction: "USER_WARNED",
      previousState,
      newState: {...previousState, warned: true},
      userPatch: {
        warningCount: FieldValue.increment(1),
        lastWarningAt: FieldValue.serverTimestamp(),
        lastWarningActionId: actionId,
      },
      expiresAtMs: null,
      authEffect: "none",
    };
  }
  case "suspend": {
    if (current === "banned") {
      throw new AdminError("user_already_banned");
    }
    if (current === "suspended") {
      throw new AdminError("user_already_suspended");
    }
    const hours = command.durationHours;
    if (!Number.isInteger(hours) || hours < MIN_SUSPENSION_HOURS || hours > MAX_SUSPENSION_HOURS) {
      throw new AdminError("invalid_argument", "durationHours");
    }
    const until = nowMs + hours * 60 * 60 * 1000;
    return {
      actionType: "TEMPORARY_SUSPENSION",
      auditAction: "USER_SUSPENDED",
      previousState,
      newState: {accountStatus: "suspended", suspendedUntil: new Date(until).toISOString(), statusActionId: actionId},
      userPatch: statusFields("suspended", command.reasonCode, until),
      expiresAtMs: until,
      authEffect: "none",
    };
  }
  case "ban": {
    if (current === "banned") {
      throw new AdminError("user_already_banned");
    }
    return {
      actionType: "PERMANENT_BAN",
      auditAction: "USER_BANNED",
      previousState,
      newState: {accountStatus: "banned", statusActionId: actionId},
      userPatch: statusFields("banned", command.reasonCode, null),
      expiresAtMs: null,
      authEffect: "disable",
    };
  }
  case "restore": {
    const legacyFlag = account.isBanned === true || account.isSuspended === true;
    const storedRestricted = ["banned", "suspended"].includes(String(account.accountStatus ?? "active"));
    if (current === "active" && !legacyFlag && !storedRestricted) {
      throw new AdminError("user_not_restricted");
    }
    return {
      actionType: "RESTORE_ACCOUNT",
      auditAction: "USER_RESTORED",
      previousState,
      newState: {accountStatus: "active", statusActionId: actionId},
      userPatch: statusFields("active", command.reasonCode, null),
      expiresAtMs: null,
      // Re-enable only what a ban disabled; a suspension never touched Auth.
      authEffect: current === "banned" || account.isBanned === true ? "enable" : "none",
    };
  }
  default:
    throw new AdminError("invalid_argument", "command");
  }
}

/**
 * Staff members are not ordinary targets. Nobody may sanction themselves, an
 * active super admin can only be sanctioned after another super admin demotes
 * them, and a colleague of equal or higher rank is out of reach.
 */
export function assertTargetActionable(
  actor: AdminActor,
  targetUid: string,
  targetStaff: ReturnType<typeof parseStaffRecord>,
): void {
  if (targetUid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  if (!targetStaff || targetStaff.status !== "active") {
    return;
  }
  if (targetStaff.role === "super_admin") {
    throw new AdminError("cannot_modify_super_admin");
  }
  if (ROLE_RANK[targetStaff.role] >= ROLE_RANK[actor.role]) {
    throw new AdminError("cannot_modify_staff");
  }
}

export interface AccountActionInput {
  targetUid: string;
  command: AccountCommand;
  internalNote: string | null;
  caseId: string | null;
  idempotencyKey: string;
  /** Set when the restore is the consequence of an accepted appeal. */
  relatedActionId?: string | null;
  appealId?: string | null;
}

export interface AccountActionResult {
  actionId: string;
  type: ActionType;
  accountStatus: string;
  suspendedUntil: string | null;
  replayed: boolean;
  authSync: string;
}

async function syncAuth(
  deps: AdminDeps,
  targetUid: string,
  effect: "disable" | "enable" | "none",
): Promise<string> {
  if (effect === "none") {
    return "not_required";
  }
  try {
    if (effect === "disable") {
      await deps.auth.updateUser(targetUid, {disabled: true});
      // Existing refresh tokens die now; the ID token in hand expires within
      // the hour and cannot be refreshed.
      await deps.auth.revokeRefreshTokens(targetUid);
    } else {
      await deps.auth.updateUser(targetUid, {disabled: false});
    }
    return "done";
  } catch (error) {
    const code = (error as {code?: string}).code;
    if (code === "auth/user-not-found") {
      return "skipped_no_auth_user";
    }
    logger.error("admin_auth_sync_failed", safeLogMeta({targetUid, effect, error: String(error)}));
    return "failed";
  }
}

export async function applyAccountAction(
  deps: AdminDeps,
  actor: AdminActor,
  input: AccountActionInput,
  requestId: string,
): Promise<AccountActionResult> {
  const db: Firestore = deps.db;
  const nowMs = deps.now();
  if (input.targetUid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  const actionId = deterministicId("act", actor.uid, input.command.kind, input.targetUid, input.idempotencyKey);
  const actionRef = db.doc(`${ACTION_COLLECTION}/${actionId}`);
  const userRef = db.doc(`users/${input.targetUid}`);
  const staffRef = db.doc(`${STAFF_COLLECTION}/${input.targetUid}`);

  const outcome = await db.runTransaction(async (tx) => {
    const actionSnap = await tx.get(actionRef);
    if (actionSnap.exists) {
      const data = actionSnap.data() ?? {};
      const newState = (data.newState ?? {}) as Record<string, unknown>;
      return {
        replayed: true,
        type: data.type as ActionType,
        accountStatus: String(newState.accountStatus ?? "unknown"),
        suspendedUntil: typeof newState.suspendedUntil === "string" ? newState.suspendedUntil : null,
        authEffect: (data.authEffect ?? "none") as "disable" | "enable" | "none",
        authSync: String(data.authSync?.status ?? "not_required"),
      };
    }
    const [userSnap, staffSnap] = await Promise.all([tx.get(userRef), tx.get(staffRef)]);
    const linkedCase = await readLinkableCase(tx, db, input.caseId);
    // Staff protection first: it must hold even for a staff login that has
    // no member account document.
    assertTargetActionable(actor, input.targetUid, parseStaffRecord(input.targetUid, staffSnap.data()));
    if (!userSnap.exists) {
      throw new AdminError("not_found", "user");
    }
    const plan = planAccountTransition(userSnap.data() ?? {}, input.command, actionId, nowMs);

    tx.create(actionRef, {
      ...buildActionRecord({
        actionId,
        type: plan.actionType,
        targetUserId: input.targetUid,
        caseId: input.caseId,
        reasonCode: input.command.reasonCode,
        internalNote: input.internalNote,
        userMessage: input.command.kind === "warn" ? input.command.userMessage : null,
        actorAdminId: actor.uid,
        actorRole: actor.role,
        requestId,
        idempotencyKey: input.idempotencyKey,
        effectiveAtMs: nowMs,
        expiresAtMs: plan.expiresAtMs,
        previousState: plan.previousState,
        newState: plan.newState,
        relatedActionId: input.relatedActionId ?? null,
      }),
      appealId: input.appealId ?? null,
      authEffect: plan.authEffect,
      authSync: {status: plan.authEffect === "none" ? "not_required" : "pending"},
    });
    tx.set(userRef, {...plan.userPatch, updatedAt: FieldValue.serverTimestamp()}, {merge: true});

    // A restore closes out the decision it reverses without editing it.
    const reversed = plan.actionType === "RESTORE_ACCOUNT"
      ? String(plan.previousState.statusActionId ?? "")
      : "";
    if (reversed) {
      tx.set(db.doc(`${ACTION_COLLECTION}/${reversed}`), {
        overturnedByActionId: actionId,
        overturnedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (linkedCase) {
      linkActionToCase(tx, db, linkedCase, {actionId, actionType: plan.actionType, actor}, nowMs);
    }
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: plan.auditAction,
      targetType: "user",
      targetId: input.targetUid,
      caseId: input.caseId,
      actionId,
      requestId,
      metadata: {
        reasonCode: input.command.reasonCode,
        ...(input.command.kind === "suspend" ? {durationHours: input.command.durationHours} : {}),
        previousStatus: plan.previousState.accountStatus,
        newStatus: plan.newState.accountStatus ?? plan.previousState.accountStatus,
        internalNote: input.internalNote ?? "",
        appealId: input.appealId ?? null,
      },
    }, nowMs);
    return {
      replayed: false,
      type: plan.actionType,
      accountStatus: String(plan.newState.accountStatus ?? plan.previousState.accountStatus),
      suspendedUntil: typeof plan.newState.suspendedUntil === "string" ? plan.newState.suspendedUntil : null,
      authEffect: plan.authEffect,
      authSync: plan.authEffect === "none" ? "not_required" : "pending",
    };
  });

  let authSync = outcome.authSync;
  // Runs on first execution and on any replay where the earlier attempt did
  // not finish, so a retried click completes the ban instead of acting twice.
  if (outcome.authEffect !== "none" && authSync !== "done" && authSync !== "skipped_no_auth_user") {
    authSync = await syncAuth(deps, input.targetUid, outcome.authEffect);
    await actionRef.set({authSync: {status: authSync, at: FieldValue.serverTimestamp()}}, {merge: true});
    if (authSync === "failed") {
      await db.doc(`adminAuditLog/aud_authsync_${actionId}_${nowMs.toString(36)}`).create({
        actorAdminId: actor.uid,
        actorRole: actor.role,
        action: "AUTH_SYNC_FAILED",
        targetType: "user",
        targetId: input.targetUid,
        caseId: input.caseId,
        actionId,
        requestId,
        metadata: {effect: outcome.authEffect},
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  }

  return {
    actionId,
    type: outcome.type,
    accountStatus: outcome.accountStatus,
    suspendedUntil: outcome.suspendedUntil,
    replayed: outcome.replayed,
    authSync,
  };
}
