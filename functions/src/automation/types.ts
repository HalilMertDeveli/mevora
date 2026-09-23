/** Job lifecycle for automationJobs/{jobId}. */
export const JobStatus = {
  queued: "queued",
  running: "running",
  succeeded: "succeeded",
  failed: "failed",
  retrying: "retrying",
  manual_review: "manual_review",
  cancelled: "cancelled",
} as const;

export type JobStatusValue = (typeof JobStatus)[keyof typeof JobStatus];

/** Automation job kinds. Keep stable — used as idempotency prefixes. */
export const JobKind = {
  orphanStorageCleanup: "orphan_storage_cleanup",
  stalePendingUploadCleanup: "stale_pending_upload_cleanup",
  deletedAccountRemnantCleanup: "deleted_account_remnant_cleanup",
  notificationRetry: "notification_retry",
  notificationRetention: "notification_retention",
  callRetention: "call_retention",
  auditLogRetention: "audit_log_retention",
  accountDeletionVerify: "account_deletion_verify",
  premiumExpirySync: "premium_expiry_sync",
  discoverEligibilityRefresh: "discover_eligibility_refresh",
  userDocumentRepair: "user_document_repair",
  reportEnqueueReview: "report_enqueue_review",
  adminManualAction: "admin_manual_action",
  // Read-only B-01 follow-up: find legacy malformed block documents. Never
  // repairs or deletes — findings go to adminReviewQueue for a human.
  forgedBlockAudit: "forged_block_audit",
} as const;

export type JobKindValue = (typeof JobKind)[keyof typeof JobKind];

export const ReviewQueueStatus = {
  open: "open",
  in_review: "in_review",
  resolved: "resolved",
  dismissed: "dismissed",
} as const;

/** Actions that must never auto-execute without admin approval. */
export const ManualReviewActions = [
  "account_ban",
  "account_permanent_delete",
  "premium_refund",
  "premium_revoke",
  "critical_report_decision",
  "force_unmatch_all",
  "mass_storage_delete",
] as const;
