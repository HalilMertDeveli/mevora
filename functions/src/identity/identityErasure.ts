import {FieldValue, getFirestore, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {DiditProvider} from "./didit/diditProvider.js";
import type {ProviderErasureOutcome} from "./identityVerificationProvider.js";

/**
 * Provider-side erasure of identity verification data.
 *
 * MEVORA deletes its own verification document as part of account deletion.
 * That is not erasure: the document images, the liveness video and the face
 * template live with the provider. This asks the provider to destroy them,
 * and — crucially — records honestly when it could not.
 *
 * A failure here must never be recorded as success and must never block the
 * account deletion it belongs to. The account goes; the outstanding provider
 * request survives as a pending record that the automation drain retries.
 */

/**
 * Outstanding provider-erasure requests: `identityErasurePending/{uid}`.
 *
 * Deliberately minimal — a uid, a provider session id, attempt bookkeeping.
 * No name, no email, no identity data. It exists *because* of a deletion
 * request and is removed the moment the provider confirms erasure, so it
 * cannot become a shadow record of a departed user.
 *
 * Server-only: `firestore.rules` denies every client read and write by
 * default, and nothing grants this collection an exception.
 */
export const IDENTITY_ERASURE_PENDING = "identityErasurePending";

export function erasurePendingRef(db: Firestore, uid: string) {
  return db.doc(`${IDENTITY_ERASURE_PENDING}/${uid}`);
}

export type ErasureAttemptResult = {
  /** True only when the provider confirmed the data is gone. */
  confirmed: boolean;
  outcome: ProviderErasureOutcome["result"] | "no_session" | "not_configured";
};

/**
 * Asks the provider to erase a session, recording a pending record if it
 * cannot be confirmed.
 *
 * Never throws: account deletion calls this on its way past, and a provider
 * outage must not abort a deletion the user has already been promised.
 */
export async function requestIdentityProviderErasure(
  input: {uid: string; providerSessionId?: string},
  db: Firestore = getFirestore(),
): Promise<ErasureAttemptResult> {
  if (!input.providerSessionId) {
    // Nothing was ever created provider-side, so there is nothing to erase.
    return {confirmed: true, outcome: "no_session"};
  }

  const provider = DiditProvider.fromEnvironment();
  if (!provider) {
    // Unconfigured: record the obligation rather than silently dropping it.
    await recordPendingErasure(db, input.uid, input.providerSessionId, "not_configured");
    return {confirmed: false, outcome: "not_configured"};
  }

  let outcome: ProviderErasureOutcome;
  try {
    outcome = await provider.requestErasure({
      uid: input.uid,
      providerSessionId: input.providerSessionId,
    });
  } catch (error) {
    logger.warn(
      "identity erasure call failed",
      safeLogMeta({uid: input.uid, error: error instanceof Error ? error.name : "unknown"}),
    );
    outcome = {result: "failedRetryable"};
  }

  // `alreadyAbsent` is a confirmation: the provider answered that the session
  // no longer exists, which is the state erasure was asking for. A repeat
  // call returning 404 is therefore success, not a failure to retry forever.
  if (outcome.result === "erased" || outcome.result === "alreadyAbsent") {
    await clearPendingErasure(db, input.uid);
    logger.info("identity erasure confirmed", safeLogMeta({uid: input.uid, outcome: outcome.result}));
    return {confirmed: true, outcome: outcome.result};
  }

  await recordPendingErasure(db, input.uid, input.providerSessionId, outcome.result);
  logger.warn("identity erasure pending", safeLogMeta({uid: input.uid, outcome: outcome.result}));
  return {confirmed: false, outcome: outcome.result};
}

async function recordPendingErasure(
  db: Firestore,
  uid: string,
  providerSessionId: string,
  reason: string,
): Promise<void> {
  await erasurePendingRef(db, uid).set(
    {
      uid,
      provider: "didit",
      providerSessionId,
      lastAttemptAt: FieldValue.serverTimestamp(),
      lastOutcome: reason,
      attempts: FieldValue.increment(1),
      createdAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

async function clearPendingErasure(db: Firestore, uid: string): Promise<void> {
  await erasurePendingRef(db, uid).delete().catch(() => undefined);
}

/**
 * Retries one pending erasure. Driven by the automation runner.
 *
 * Returns `complete: false` when the provider still has not confirmed, which
 * the runner routes to manual review rather than to `failed` — an unerased
 * identity document is a compliance matter, not a transient error, and a
 * human should see it.
 */
export async function runIdentityErasureJob(
  uid: string,
  db: Firestore = getFirestore(),
): Promise<{complete: boolean; outcome: string}> {
  const snap = await erasurePendingRef(db, uid).get();
  if (!snap.exists) {
    // Already erased and cleared by an earlier attempt.
    return {complete: true, outcome: "already_cleared"};
  }
  const providerSessionId = snap.data()?.providerSessionId as string | undefined;
  const result = await requestIdentityProviderErasure({uid, providerSessionId}, db);
  return {complete: result.confirmed, outcome: result.outcome};
}
