/**
 * Audit vocabulary. One entry per security-relevant event the admin platform
 * produces. The list is closed: an event that is not named here cannot be
 * written, so the log stays queryable by `action`.
 */
export const AUDIT_ACTIONS = [
  "ADMIN_LOGIN",
  "SENSITIVE_PROFILE_VIEWED",

  "CASE_CREATED",
  "CASE_ASSIGNED",
  "CASE_UNASSIGNED",
  "CASE_STATUS_CHANGED",
  "CASE_RESOLVED",
  "CASE_ESCALATED",
  "CASE_NOTE_ADDED",

  "REPORT_RESOLVED",

  "USER_WARNED",
  "USER_SUSPENDED",
  "USER_BANNED",
  "USER_RESTORED",
  "USER_SUSPENSION_EXPIRED",
  "AUTH_SYNC_FAILED",

  "PHOTO_APPROVED",
  "PHOTO_REJECTED",
  "PHOTO_REMOVED",
  "PHOTO_ESCALATED",

  "HUMOR_APPROVED",
  "HUMOR_REJECTED",
  "HUMOR_ESCALATED",

  "VERIFICATION_REVERIFICATION_REQUIRED",
  "VERIFICATION_ESCALATED",

  "SUPPORT_ASSIGNED",
  "SUPPORT_REPLIED",
  "SUPPORT_STATUS_CHANGED",
  "SUPPORT_RESOLVED",
  "SUPPORT_ESCALATED",
  "SUPPORT_NOTE_ADDED",

  "AUTOMATION_JOB_RETRIED",
  "AUTOMATION_JOB_RESOLVED",
  "AUTOMATION_JOB_DISMISSED",
  "AUTOMATION_JOB_ESCALATED",
  "REVIEW_ITEM_RESOLVED",

  "APPEAL_SUBMITTED",
  "APPEAL_OPENED_BY_STAFF",
  "APPEAL_ASSIGNED",
  "APPEAL_ACCEPTED",
  "APPEAL_REJECTED",

  "ADMIN_CREATED",
  "ADMIN_GRANTED",
  "ADMIN_ROLE_CHANGED",
  "ADMIN_DISABLED",
  "ADMIN_ENABLED",
  "ADMIN_SESSIONS_REVOKED",
  "ADMIN_ACTIVATION_ISSUED",

  "MAINTENANCE_RUN",

  "APP_MAINTENANCE_ENABLED",
  "APP_MAINTENANCE_DISABLED",
  "APP_MIN_VERSION_CHANGED",
  "APP_FEATURE_SWITCH_CHANGED",
  "APP_ANNOUNCEMENT_CHANGED",
] as const;

export type AuditAction = (typeof AUDIT_ACTIONS)[number];

export const AUDIT_TARGET_TYPES = [
  "user",
  "case",
  "report",
  "photo",
  "humor_content",
  "support_ticket",
  "verification",
  "automation_job",
  "review_item",
  "appeal",
  "staff",
  "app_config",
  "system",
] as const;

export type AuditTargetType = (typeof AUDIT_TARGET_TYPES)[number];

export interface AuditEventInput {
  /** Staff uid, or "system" for scheduled work. */
  actorAdminId: string;
  actorRole?: string | null;
  action: AuditAction;
  targetType: AuditTargetType;
  targetId: string;
  caseId?: string | null;
  actionId?: string | null;
  requestId?: string | null;
  metadata?: Record<string, unknown>;
}
