import {FieldValue} from "firebase-admin/firestore";
import {requireIdentityReverification} from "../../identity/identityVerificationStore.js";
import {ACTION_COLLECTION, buildActionRecord} from "../actions/actionTypes.js";
import {appendAuditEvent, recordAuditEvent} from "../audit/auditService.js";
import type {AdminActor} from "../auth/adminAuthorization.js";
import {openOrAttachCase} from "../cases/caseService.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {cursorPart, decodeCursor, deterministicId, encodeCursor, iso} from "../validation.js";
import {loadUserCards} from "../users/userCards.js";

/**
 * Identity verification in the console — read, escalate, require again.
 *
 * The console sees only what MEVORA already stores in
 * users/{uid}/verification/identity: provider, status, normalised reason,
 * timestamps and attempt counts. Document images, selfies, liveness video,
 * biometric templates, MRZ data and raw provider payloads are never stored by
 * MEVORA, so there is nothing here that could show them.
 *
 * ABSOLUTE RULE: there is no command that marks a member verified. Only the
 * provider's authenticated webhook, through applyIdentityProviderEvent, can
 * grant the badge. The console can take it away (require re-verification)
 * and can escalate; that is all.
 */

export const VERIFICATION_QUEUE_FILTERS = ["in_review", "error", "declined", "expired"] as const;
export type VerificationQueueFilter = (typeof VERIFICATION_QUEUE_FILTERS)[number];

function maskSessionId(value: unknown): string | null {
  return typeof value === "string" && value.length > 6 ? `…${value.slice(-6)}` : null;
}

export async function getVerification(deps: AdminDeps, uid: string) {
  const {db} = deps;
  const [identity, legacy, account] = await Promise.all([
    db.doc(`users/${uid}/verification/identity`).get(),
    db.doc(`users/${uid}/verification/sumsub`).get(),
    db.doc(`users/${uid}`).get(),
  ]);
  if (!account.exists) {
    throw new AdminError("not_found", "user");
  }
  const v = identity.data();
  return {
    uid,
    isVerified: account.get("isVerified") === true,
    identity: v
      ? {
        provider: v.provider ?? null,
        status: v.status ?? "not_started",
        reason: v.reason ?? null,
        createdAt: iso(v.createdAt),
        updatedAt: iso(v.updatedAt),
        verifiedAt: iso(v.verifiedAt),
        attemptCount: typeof v.attemptCount === "number" ? v.attemptCount : 0,
        lastAttemptAt: iso(v.lastAttemptAt),
        // Correlation handle for the provider console, shortened: enough to
        // find a session, not a credential.
        providerSessionRef: maskSessionId(v.providerSessionId),
        reverificationRequired: v.reverificationRequired === true,
        reverificationRequiredAt: iso(v.reverificationRequiredAt),
      }
      : null,
    legacy: legacy.exists
      ? {provider: "sumsub", status: legacy.get("status") ?? null, updatedAt: iso(legacy.get("updatedAt"))}
      : null,
  };
}

export async function listVerificationReviews(
  deps: AdminDeps,
  input: {filter: VerificationQueueFilter; cursor: unknown; limit: number},
) {
  const {db} = deps;
  let q = db.collectionGroup("verification")
    .where("status", "==", input.filter)
    .orderBy("updatedAt", "desc")
    .orderBy("__name__", "desc");
  const after = decodeCursor(input.cursor, 2);
  if (after) {
    q = q.startAfter(...after);
  }
  const snap = await q.limit(input.limit).get();
  const uids = snap.docs.map((doc) => doc.ref.path.split("/")[1] ?? "");
  const cards = await loadUserCards(db, uids, deps.now());
  const last = snap.docs[snap.docs.length - 1];
  return {
    items: snap.docs.map((doc, index) => ({
      uid: uids[index],
      document: doc.id,
      provider: doc.get("provider") ?? (doc.id === "sumsub" ? "sumsub" : null),
      status: doc.get("status") ?? null,
      reason: doc.get("reason") ?? null,
      attemptCount: typeof doc.get("attemptCount") === "number" ? doc.get("attemptCount") : 0,
      updatedAt: iso(doc.get("updatedAt")),
      reverificationRequired: doc.get("reverificationRequired") === true,
      user: cards.get(uids[index]) ?? null,
    })),
    nextCursor: snap.docs.length === input.limit && last
      ? encodeCursor([cursorPart(last.get("updatedAt")), last.ref.path])
      : null,
  };
}

export async function requireReverification(
  deps: AdminDeps,
  actor: AdminActor,
  input: {uid: string; reasonCode: string; internalNote: string | null; caseId: string | null; idempotencyKey: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  if (input.uid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  const actionId = deterministicId("act", actor.uid, "reverify", input.uid, input.idempotencyKey);
  const actionRef = db.doc(`${ACTION_COLLECTION}/${actionId}`);
  const existing = await actionRef.get();
  if (existing.exists) {
    return {uid: input.uid, actionId, replayed: true};
  }
  const account = await db.doc(`users/${input.uid}`).get();
  if (!account.exists) {
    throw new AdminError("not_found", "user");
  }
  const outcome = await requireIdentityReverification(db, input.uid, {actionId, nowMs});
  await db.runTransaction(async (tx) => {
    const again = await tx.get(actionRef);
    if (again.exists) {
      return;
    }
    tx.create(actionRef, buildActionRecord({
      actionId,
      type: "REQUIRE_REVERIFICATION",
      targetUserId: input.uid,
      caseId: input.caseId,
      reasonCode: input.reasonCode,
      internalNote: input.internalNote,
      actorAdminId: actor.uid,
      actorRole: actor.role,
      requestId,
      idempotencyKey: input.idempotencyKey,
      effectiveAtMs: nowMs,
      previousState: {verificationStatus: outcome.previousStatus, isVerified: outcome.wasVerified},
      newState: {verificationStatus: "expired", isVerified: false, reverificationRequired: true},
    }));
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "VERIFICATION_REVERIFICATION_REQUIRED",
      targetType: "verification",
      targetId: input.uid,
      caseId: input.caseId,
      actionId,
      requestId,
      metadata: {
        reasonCode: input.reasonCode,
        previousStatus: outcome.previousStatus,
        wasVerified: outcome.wasVerified,
        internalNote: input.internalNote ?? "",
      },
    }, nowMs);
    if (input.caseId) {
      tx.set(db.doc(`moderationCases/${input.caseId}`), {
        actionIds: FieldValue.arrayUnion(actionId),
        lastActivityAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  return {uid: input.uid, actionId, replayed: false, previousStatus: outcome.previousStatus};
}

export async function escalateVerification(
  deps: AdminDeps,
  actor: AdminActor,
  input: {uid: string; reason: string; note: string | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const snap = await db.doc(`users/${input.uid}/verification/identity`).get();
  const account = await db.doc(`users/${input.uid}`).get();
  if (!account.exists) {
    throw new AdminError("not_found", "user");
  }
  const {caseId} = await openOrAttachCase(db, {
    type: "VERIFICATION_REVIEW",
    correlationKey: `verification:${input.uid}`,
    subjectUserId: input.uid,
    sourceRef: `users/${input.uid}/verification/identity`,
    reasonCode: input.reason,
    priority: "high",
    summary: `Verification review (${snap.get("status") ?? "not_started"})`,
    createdBy: actor.uid,
    createdByRole: actor.role,
    requestId,
  }, nowMs);
  await recordAuditEvent(db, {
    actorAdminId: actor.uid,
    actorRole: actor.role,
    action: "VERIFICATION_ESCALATED",
    targetType: "verification",
    targetId: input.uid,
    caseId,
    requestId,
    metadata: {reason: input.reason, status: snap.get("status") ?? "not_started", internalNote: input.note ?? ""},
  }, nowMs);
  return {uid: input.uid, caseId};
}
