import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {claimJob, completeJob, failJob, markManualReview} from "./jobs.js";
import {JobKind} from "./types.js";
import {verifyAccountDeletion} from "./deletionVerify.js";
import {runIdentityErasureJob} from "../identity/identityErasure.js";
import {auditForgedBlocks} from "./forgedBlockAudit.js";
import {safeLogMeta} from "../security/logHygiene.js";

export type ProcessJobOutcome =
  | {jobId: string; processed: false; reason: string}
  | {jobId: string; processed: true; status: string};

/**
 * A failure that retrying cannot fix — an unknown job kind or a malformed
 * payload. Marked terminal so the job lands in `failed` for inspection instead
 * of burning its retry budget.
 */
class PermanentJobError extends Error {
  readonly permanent = true;
}

/**
 * Run a single job's handler. Throws so the caller can record the failure
 * against the job document.
 */
async function runHandler(
  kind: string,
  payload: Record<string, unknown>,
  db: Firestore,
): Promise<{result: Record<string, unknown>; needsManualReview: boolean}> {
  switch (kind) {
  case JobKind.accountDeletionVerify: {
    const uid = String(payload.uid ?? "");
    if (!uid) {
      throw new PermanentJobError("uid_required");
    }
    const result = await verifyAccountDeletion(uid, db);
    // An incomplete deletion is a compliance issue, not a transient error:
    // retrying cannot fix it, so route it to a human instead of `failed`.
    return {result: {...result}, needsManualReview: !result.complete};
  }
  case JobKind.identityProviderErasure: {
    const uid = String(payload.uid ?? "");
    if (!uid) {
      throw new PermanentJobError("uid_required");
    }
    const result = await runIdentityErasureJob(uid, db);
    // Identity documents the provider still holds for a deleted user is a
    // compliance matter, not a transient error. Route it to a human rather
    // than letting it exhaust a retry budget and disappear into `failed`.
    return {result: {...result}, needsManualReview: !result.complete};
  case JobKind.forgedBlockAudit: {
    const result = await auditForgedBlocks({
      db,
      pageSize: typeof payload.pageSize === "number" ? payload.pageSize : undefined,
      maxPages: typeof payload.maxPages === "number" ? payload.maxPages : undefined,
      startAfterId: typeof payload.startAfterId === "string" ? payload.startAfterId : null,
      jobId: typeof payload.jobId === "string" ? payload.jobId : undefined,
    });
    // Anything flagged is a safety record a human must judge — the audit
    // deliberately cannot repair it. An incomplete scan also needs a human to
    // resume from nextCursor, so neither case silently reports "succeeded".
    return {result, needsManualReview: result.flagged > 0 || !result.complete};
  }
  default:
    throw new PermanentJobError(`unknown_job_kind:${kind}`);
  }
}

/**
 * Claim and execute one `automationJobs` document. Safe to call concurrently:
 * `claimJob` transitions queued/retrying -> running in a transaction, so a
 * second caller for the same job is a no-op.
 */
export async function processJobById(
  jobId: string,
  db: Firestore = getFirestore(),
): Promise<ProcessJobOutcome> {
  const job = await claimJob(jobId, db);
  if (!job) {
    return {jobId, processed: false, reason: "not_claimable"};
  }

  try {
    const {result, needsManualReview} = await runHandler(job.kind, job.payload, db);
    if (needsManualReview) {
      await markManualReview(jobId, `incomplete:${job.kind}`, db);
      await db.doc(`automationJobs/${jobId}`).set({result}, {merge: true});
      logger.warn("automation job needs manual review", safeLogMeta({jobId, kind: job.kind}));
      return {jobId, processed: true, status: "manual_review"};
    }
    await completeJob(jobId, result, db);
    return {jobId, processed: true, status: "succeeded"};
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const retry = !(error instanceof PermanentJobError);
    const status = await failJob(
      jobId,
      message,
      {attempts: job.attempts, maxAttempts: job.maxAttempts, retry},
      db,
    );
    logger.error("automation job failed", safeLogMeta({jobId, kind: job.kind, status}));
    return {jobId, processed: true, status};
  }
}
