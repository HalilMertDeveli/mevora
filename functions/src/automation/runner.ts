import {logger} from "firebase-functions";
import {
  claimJob,
  completeJob,
  failJob,
  enqueueJob,
} from "./jobs.js";
import {JobKind} from "./types.js";
import {
  cleanupDeletedAccountStorageRemnants,
  cleanupOldAuditLogs,
  cleanupOldCalls,
  cleanupOldNotifications,
  cleanupOrphanChatMedia,
  cleanupStalePendingUploads,
  refreshDiscoverEligibilityBatch,
} from "./cleanup.js";
import {retryFailedNotifications} from "./notificationRetry.js";
import {verifyAccountDeletion, repairUserDocument} from "./deletionVerify.js";
import {syncExpiredPremium} from "./premiumSync.js";
import type {CleanupOptions} from "./types.js";

function cleanupOpts(payload: Record<string, unknown>): CleanupOptions {
  return {
    dryRun: payload.dryRun === true,
    limit: Math.min(500, Math.max(1, Number(payload.limit ?? 100))),
    requireAdminApproval: payload.requireAdminApproval === true,
    adminUid: typeof payload.adminUid === "string" ? payload.adminUid : undefined,
    reason: typeof payload.reason === "string" ? payload.reason : undefined,
  };
}

/** Execute a claimed automation job by kind. Idempotent per jobId. */
export async function processJobById(jobId: string): Promise<{
  status: string;
  result?: Record<string, unknown>;
}> {
  const job = await claimJob(jobId);
  if (!job) {
    return {status: "skipped"};
  }
  try {
    const result = await runKind(job.kind, job.payload);
    await completeJob(jobId, result);
    return {status: "succeeded", result};
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logger.error("automation job failed", {jobId, kind: job.kind, message});
    const status = await failJob(jobId, message, {
      attempts: job.attempts,
      maxAttempts: job.maxAttempts,
      retry: true,
    });
    return {status};
  }
}

async function runKind(
  kind: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const opts = cleanupOpts(payload);
  switch (kind) {
  case JobKind.orphanStorageCleanup:
    return cleanupOrphanChatMedia(opts);
  case JobKind.stalePendingUploadCleanup:
    return cleanupStalePendingUploads(opts);
  case JobKind.deletedAccountRemnantCleanup:
    return cleanupDeletedAccountStorageRemnants(opts);
  case JobKind.notificationRetention:
    return cleanupOldNotifications(opts);
  case JobKind.callRetention:
    return cleanupOldCalls(opts);
  case JobKind.auditLogRetention:
    return cleanupOldAuditLogs(opts);
  case JobKind.notificationRetry:
    return retryFailedNotifications(opts.limit);
  case JobKind.accountDeletionVerify: {
    const uid = String(payload.uid ?? "");
    if (!uid) {
      throw new Error("uid_required");
    }
    return verifyAccountDeletion(uid);
  }
  case JobKind.premiumExpirySync:
    return syncExpiredPremium(opts);
  case JobKind.discoverEligibilityRefresh:
    return refreshDiscoverEligibilityBatch(opts);
  case JobKind.userDocumentRepair: {
    const uid = String(payload.uid ?? "");
    if (!uid) {
      throw new Error("uid_required");
    }
    return repairUserDocument(uid);
  }
  default:
    throw new Error(`unknown_job_kind:${kind}`);
  }
}

/** Enqueue daily low-risk cleanup suite (dry-run false for retention; storage starts dry). */
export async function enqueueDailyCleanupSuite(createdBy = "scheduler"): Promise<string[]> {
  const day = new Date().toISOString().slice(0, 10);
  const ids: string[] = [];
  const specs: Array<{kind: string; key: string; payload: Record<string, unknown>}> = [
    {
      kind: JobKind.notificationRetention,
      key: `notif_retention_${day}`,
      payload: {dryRun: false, limit: 400},
    },
    {
      kind: JobKind.callRetention,
      key: `call_retention_${day}`,
      payload: {dryRun: false, limit: 200},
    },
    {
      kind: JobKind.notificationRetry,
      key: `notif_retry_${day}_hourly`,
      payload: {limit: 50},
    },
    {
      kind: JobKind.stalePendingUploadCleanup,
      key: `stale_pending_${day}`,
      payload: {dryRun: false, limit: 100},
    },
    {
      kind: JobKind.orphanStorageCleanup,
      key: `orphan_chat_${day}`,
      payload: {dryRun: true, limit: 100},
    },
    {
      kind: JobKind.deletedAccountRemnantCleanup,
      key: `deleted_remnant_${day}`,
      payload: {dryRun: true, limit: 50},
    },
    {
      kind: JobKind.premiumExpirySync,
      key: `premium_sync_${day}`,
      payload: {dryRun: false, limit: 200},
    },
    {
      kind: JobKind.discoverEligibilityRefresh,
      key: `discover_refresh_${day}`,
      payload: {dryRun: false, limit: 200},
    },
  ];
  for (const spec of specs) {
    const {jobId} = await enqueueJob({
      kind: spec.kind,
      idempotencyKey: spec.key,
      payload: spec.payload,
      createdBy,
    });
    ids.push(jobId);
  }
  return ids;
}
