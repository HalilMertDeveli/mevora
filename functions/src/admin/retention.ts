import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {effectiveAccountStatus} from "../profileSafety.js";
import {ACTION_COLLECTION, buildActionRecord} from "./actions/actionTypes.js";
import {AUDIT_COLLECTION, appendAuditEvent} from "./audit/auditService.js";
import {CASE_COLLECTION} from "./cases/caseTypes.js";
import type {AdminBucketPort} from "./deps.js";
import {deterministicId, toMillis} from "./validation.js";

/**
 * Scheduled upkeep for the Trust & Safety collections.
 *
 * Suspension expiry — a suspension ends by itself (effectiveAccountStatus
 * already treats it as over); the sweep rewrites the stored state and records
 * a SUSPENSION_EXPIRED action so the account document and history agree.
 *
 * Retention — indefinite retention is not assumed. The horizons below are the
 * documented policy (docs/ADMIN_TRUST_SAFETY_ARCHITECTURE.md §Retention).
 * They are a legal / business decision the owner confirms; until
 * ADMIN_RETENTION_ENFORCE=true is set on the functions the sweep only counts
 * what it would remove and logs it (dry run). Operational scratch data —
 * rate-limit windows — is always pruned.
 */

export const RETENTION_POLICY = {
  auditLogDays: 730,
  closedCaseDays: 730,
  resolvedAppealDays: 730,
  /** Actions still backing a live ban are kept regardless of age. */
  moderationActionDays: 1095,
  quarantinedPhotoDays: 90,
  rateLimitWindowDays: 2,
} as const;

const SWEEP_BATCH = 200;
const DAY_MS = 24 * 60 * 60 * 1000;

export async function expireSuspensions(db: Firestore, nowMs: number): Promise<number> {
  const snap = await db.collection("users")
    .where("accountStatus", "==", "suspended")
    .where("suspendedUntil", "<=", Timestamp.fromMillis(nowMs))
    .limit(SWEEP_BATCH)
    .get();
  let expired = 0;
  for (const doc of snap.docs) {
    const done = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const data = fresh.data();
      if (!data || data.accountStatus !== "suspended" || effectiveAccountStatus(data, nowMs) !== "active") {
        return false;
      }
      const previousActionId = typeof data.statusActionId === "string" ? data.statusActionId : "";
      const actionId = deterministicId("act", "system", "suspension_expired", doc.id, previousActionId || String(toMillis(data.suspendedUntil)));
      const actionRef = db.doc(`${ACTION_COLLECTION}/${actionId}`);
      if ((await tx.get(actionRef)).exists) {
        return false;
      }
      tx.create(actionRef, buildActionRecord({
        actionId,
        type: "SUSPENSION_EXPIRED",
        targetUserId: doc.id,
        caseId: null,
        reasonCode: "SUSPENSION_EXPIRED",
        internalNote: null,
        actorAdminId: "system",
        actorRole: "system",
        requestId: null,
        idempotencyKey: null,
        effectiveAtMs: nowMs,
        previousState: {accountStatus: "suspended", statusActionId: previousActionId || null},
        newState: {accountStatus: "active", statusActionId: actionId},
        relatedActionId: previousActionId || null,
      }));
      tx.set(doc.ref, {
        accountStatus: "active",
        isSuspended: false,
        suspendedUntil: null,
        statusReasonCode: "SUSPENSION_EXPIRED",
        statusActionId: actionId,
        statusUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      appendAuditEvent(tx, db, {
        actorAdminId: "system",
        actorRole: "system",
        action: "USER_SUSPENSION_EXPIRED",
        targetType: "user",
        targetId: doc.id,
        actionId,
        metadata: {previousActionId: previousActionId || null},
      }, nowMs);
      return true;
    });
    if (done) {
      expired += 1;
    }
  }
  return expired;
}

async function sweep(
  db: Firestore,
  label: string,
  query: FirebaseFirestore.Query,
  enforce: boolean,
  onDelete?: (doc: FirebaseFirestore.QueryDocumentSnapshot) => Promise<void>,
): Promise<number> {
  const snap = await query.limit(SWEEP_BATCH).get();
  if (!enforce || snap.empty) {
    return snap.size;
  }
  for (const doc of snap.docs) {
    if (onDelete) {
      await onDelete(doc);
    }
  }
  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  logger.info("admin_retention_deleted", {label, count: snap.size});
  return snap.size;
}

export async function runRetentionSweep(
  db: Firestore,
  bucket: () => AdminBucketPort,
  nowMs: number,
  enforce: boolean,
): Promise<Record<string, number>> {
  const before = (days: number) => Timestamp.fromMillis(nowMs - days * DAY_MS);
  const result: Record<string, number> = {};

  // Always: rate-limit windows are scratch state, not records.
  result.rateLimits = await sweep(
    db,
    "adminRateLimits",
    db.collection("adminRateLimits").where("updatedAt", "<", before(RETENTION_POLICY.rateLimitWindowDays)),
    true,
  );

  result.auditLog = await sweep(
    db,
    AUDIT_COLLECTION,
    db.collection(AUDIT_COLLECTION).where("createdAt", "<", before(RETENTION_POLICY.auditLogDays)),
    enforce,
  );
  result.closedCases = await sweep(
    db,
    CASE_COLLECTION,
    db.collection(CASE_COLLECTION)
      .where("status", "in", ["resolved", "dismissed"])
      .where("resolvedAt", "<", before(RETENTION_POLICY.closedCaseDays)),
    enforce,
    async (doc) => {
      const notes = await doc.ref.collection("notes").limit(500).get();
      const batch = db.batch();
      notes.docs.forEach((n) => batch.delete(n.ref));
      await batch.commit();
    },
  );
  result.resolvedAppeals = await sweep(
    db,
    "appeals",
    db.collection("appeals")
      .where("status", "==", "resolved")
      .where("resolvedAt", "<", before(RETENTION_POLICY.resolvedAppealDays)),
    enforce,
  );

  // Actions: old ones go, except the one a live ban still rests on.
  const oldActions = await db.collection(ACTION_COLLECTION)
    .where("createdAt", "<", before(RETENTION_POLICY.moderationActionDays))
    .limit(SWEEP_BATCH)
    .get();
  const removable = [];
  for (const doc of oldActions.docs) {
    const target = doc.get("targetUserId");
    if (typeof target === "string" && target) {
      const account = await db.doc(`users/${target}`).get();
      if (account.exists && account.get("statusActionId") === doc.id) {
        continue;
      }
    }
    removable.push(doc);
  }
  if (enforce && removable.length) {
    const batch = db.batch();
    removable.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
  result.moderationActions = removable.length;

  // Quarantined photo bytes outlive the appeal window only by the policy.
  try {
    const [files] = await bucket().getFiles({prefix: "moderation/quarantine/", maxResults: SWEEP_BATCH, autoPaginate: false});
    let stale = 0;
    for (const file of files) {
      const [metadata] = await bucket().file(file.name).getMetadata();
      const created = Date.parse(String((metadata as {timeCreated?: string}).timeCreated ?? ""));
      if (!Number.isNaN(created) && created < nowMs - RETENTION_POLICY.quarantinedPhotoDays * DAY_MS) {
        stale += 1;
        if (enforce) {
          await bucket().file(file.name).delete({ignoreNotFound: true});
        }
      }
    }
    result.quarantinedPhotos = stale;
  } catch (error) {
    logger.warn("admin_retention_quarantine_skipped", {error: String(error)});
  }

  logger.info("admin_retention_sweep", {enforce, ...result});
  return result;
}
