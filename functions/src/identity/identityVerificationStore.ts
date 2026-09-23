import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {
  IDENTITY_VERIFICATION_SCHEMA_VERSION,
  canStartIdentitySession,
  parseIdentityVerificationDoc,
  shouldApplyEvent,
  type IdentityVerificationDoc,
  type StartBlockReason,
} from "./identityVerificationRecord.js";
import {
  IDENTITY_VERIFICATION_DOC_ID,
  grantsVerifiedBadge,
  type IdentityVerificationProvider,
  type IdentityVerificationStatus,
} from "./identityVerificationStatus.js";
import type {
  IdentityVerificationReasonCode,
  ProviderWebhookEvent,
} from "./identityVerificationProvider.js";

/**
 * The only writer of MEVORA's verification state.
 *
 * Two operations, both transactional: reserve an attempt before creating a
 * provider session, and apply an authenticated provider decision. Nothing
 * else in the codebase may write `users/{uid}/verification/identity` or
 * `users/{uid}.isVerified`.
 */

export function identityVerificationRef(db: Firestore, uid: string) {
  return db.doc(`users/${uid}/verification/${IDENTITY_VERIFICATION_DOC_ID}`);
}

export async function readIdentityVerification(
  db: Firestore,
  uid: string,
): Promise<IdentityVerificationDoc> {
  const snap = await identityVerificationRef(db, uid).get();
  return parseIdentityVerificationDoc(snap.data());
}

export class IdentityStartBlockedError extends Error {
  constructor(
    readonly reason: StartBlockReason,
    readonly retryAfterSeconds?: number,
  ) {
    super(reason);
    this.name = "IdentityStartBlockedError";
  }
}

/**
 * Reserves an attempt, returning any session that may be resumed instead.
 *
 * Called before the provider is contacted so two rapid taps cannot produce
 * two provider sessions: the first transaction moves the document to
 * `pending`, and the second sees an in-flight state and is refused.
 *
 * The attempt counter rolls over a day after the last attempt rather than on
 * a calendar boundary, matching the gate in `canStartIdentitySession`.
 */
export async function reserveIdentitySessionAttempt(
  db: Firestore,
  uid: string,
  provider: IdentityVerificationProvider,
  nowMs: number = Date.now(),
): Promise<{resumableSessionId?: string}> {
  return db.runTransaction(async (tx) => {
    const ref = identityVerificationRef(db, uid);
    const snap = await tx.get(ref);
    const existing = parseIdentityVerificationDoc(snap.data());

    const gate = canStartIdentitySession(existing, nowMs);
    if (!gate.allowed) {
      // An in-flight session is resumable rather than an error: the user
      // probably backgrounded the app mid-flow. The caller re-hands them the
      // same provider session instead of burning another attempt.
      if (gate.reason === "in_flight" && existing.providerSessionId) {
        return {resumableSessionId: existing.providerSessionId};
      }
      throw new IdentityStartBlockedError(gate.reason ?? "attempt_limit", gate.retryAfterSeconds);
    }

    const lastAttemptMs = existing.lastAttemptAt?.toMillis();
    const withinDay =
      lastAttemptMs !== undefined && nowMs - lastAttemptMs < 24 * 60 * 60 * 1000;
    const nextCount = withinDay ? existing.attemptCount + 1 : 1;

    tx.set(
      ref,
      {
        schemaVersion: IDENTITY_VERIFICATION_SCHEMA_VERSION,
        provider,
        status: "pending" satisfies IdentityVerificationStatus,
        attemptCount: nextCount,
        lastAttemptAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        ...(snap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
        // A new attempt clears the previous verdict's reason so a stale
        // "face_mismatch" cannot be shown against a fresh session.
        reason: FieldValue.delete(),
      },
      {merge: true},
    );
    return {};
  });
}

/** Records the provider session id once the provider has actually issued one. */
export async function attachProviderSession(
  db: Firestore,
  uid: string,
  providerSessionId: string,
): Promise<void> {
  await identityVerificationRef(db, uid).set(
    {
      providerSessionId,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

export type ApplyEventResult =
  | {applied: true; status: IdentityVerificationStatus}
  | {applied: false; skipped: "duplicate" | "stale" | "session_mismatch" | "no_such_user"};

/**
 * Applies an authenticated provider decision.
 *
 * Every refusal here is deliberate:
 *
 *  - `no_such_user` — the account was deleted. Writing would resurrect a
 *    departed user's verification state, so a late webhook is dropped.
 *  - `session_mismatch` — the event names a session this user never started.
 *    An authentic signature proves the event came from Didit, not that it
 *    belongs to this uid; both must hold.
 *  - `duplicate` / `stale` — redelivery and reordering, handled by
 *    `shouldApplyEvent`.
 *
 * `users/{uid}.isVerified` is written in the same transaction as the
 * verification document so the badge and the state behind it cannot diverge.
 */
export async function applyIdentityProviderEvent(
  db: Firestore,
  event: ProviderWebhookEvent,
  provider: IdentityVerificationProvider,
): Promise<ApplyEventResult> {
  const verificationRef = identityVerificationRef(db, event.uid);
  const userRef = db.doc(`users/${event.uid}`);
  // The public card. It carries the badge and nothing else — no session id,
  // no reason, no timestamps.
  const profileRef = db.doc(`profiles/${event.uid}`);

  return db.runTransaction(async (tx) => {
    const [verificationSnap, userSnap] = await Promise.all([
      tx.get(verificationRef),
      tx.get(userRef),
    ]);

    if (!userSnap.exists) {
      return {applied: false, skipped: "no_such_user"} as const;
    }

    const existing = parseIdentityVerificationDoc(verificationSnap.data());

    if (
      existing.providerSessionId &&
      existing.providerSessionId !== event.providerSessionId
    ) {
      return {applied: false, skipped: "session_mismatch"} as const;
    }

    const decision = shouldApplyEvent(existing, event);
    if (!decision.apply) {
      return {applied: false, skipped: decision.skipReason ?? "stale"} as const;
    }

    const verified = grantsVerifiedBadge(event.status);
    const update: Record<string, unknown> = {
      schemaVersion: IDENTITY_VERIFICATION_SCHEMA_VERSION,
      provider,
      providerSessionId: event.providerSessionId,
      status: event.status,
      reason: event.reason ?? FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
      lastEventId: event.eventId,
      lastEventAtMs: event.occurredAtMs,
      ...(verificationSnap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      ...(verified ? {verifiedAt: FieldValue.serverTimestamp()} : {}),
    };
    tx.set(verificationRef, update, {merge: true});

    // The badge follows the state exactly: set on verified, cleared on any
    // terminal non-verified outcome. An in-flight status leaves it alone so a
    // re-verification does not strip an existing badge mid-flow.
    if (verified) {
      const badge = {isVerified: true, updatedAt: FieldValue.serverTimestamp()};
      tx.set(userRef, badge, {merge: true});
      tx.set(profileRef, badge, {merge: true});
    } else if (event.status === "declined" || event.status === "expired") {
      const badge = {isVerified: false, updatedAt: FieldValue.serverTimestamp()};
      tx.set(userRef, badge, {merge: true});
      tx.set(profileRef, badge, {merge: true});
    }

    return {applied: true, status: event.status} as const;
  });
}

/** Reason codes, re-exported so callers need not reach into the provider module. */
export type {IdentityVerificationReasonCode};
