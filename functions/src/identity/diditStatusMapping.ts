import type {IdentityVerificationStatus} from "./identityVerificationStatus.js";

/**
 * Didit session statuses, verbatim from the current official docs
 * (https://docs.didit.me/integration/verification-statuses).
 *
 * They are case-sensitive strings *with spaces* — "In Review", not
 * "in_review" — and "Kyc Expired" carries a single capital K. Matching is
 * exact on purpose: a near-miss must surface as `error`, never silently
 * become `not_started`.
 */
export type DiditSessionStatus =
  | "Not Started"
  | "In Progress"
  | "Awaiting User"
  | "In Review"
  | "Resubmitted"
  | "Approved"
  | "Declined"
  | "Expired"
  | "Abandoned"
  | "Kyc Expired";

const DIDIT_STATUS_MAP: Record<DiditSessionStatus, IdentityVerificationStatus> = {
  "Not Started": "not_started",
  "In Progress": "in_progress",
  "Awaiting User": "pending",
  "Resubmitted": "in_progress",
  "In Review": "in_review",
  "Approved": "verified",
  "Declined": "declined",
  // Session timed out before the user opened it, or the user walked away.
  // Both are recoverable by creating a new session, so they are not declines.
  "Expired": "expired",
  "Abandoned": "expired",
  // A previously approved session aged out of the workflow's KYC validity
  // window. The user is no longer verified and must re-verify.
  "Kyc Expired": "expired",
};

/**
 * Maps a raw Didit webhook/session `status` to MEVORA's internal vocabulary.
 *
 * An unrecognised status maps to `error` rather than to a guess: a provider
 * that adds a status MEVORA has not reviewed must not be able to move a user
 * into or out of the verified state by accident.
 */
export function mapDiditStatus(raw: unknown): IdentityVerificationStatus {
  if (typeof raw !== "string" || raw.length === 0) {
    return "error";
  }
  const mapped = DIDIT_STATUS_MAP[raw as DiditSessionStatus];
  return mapped ?? "error";
}

/** Envelope fields MEVORA reads off a Didit `status.updated` webhook. */
export type DiditWebhookEnvelope = {
  webhook_type?: string;
  session_id?: string;
  vendor_data?: string;
  status?: string;
  timestamp?: number;
  environment?: string;
};

/**
 * `vendor_data` carries the MEVORA uid that created the session. It is the
 * only correlation key; a webhook without it cannot be attributed to a user
 * and must be rejected rather than guessed at.
 */
export function correlationUidFromWebhook(payload: DiditWebhookEnvelope): string | null {
  const uid = typeof payload.vendor_data === "string" ? payload.vendor_data.trim() : "";
  return uid.length > 0 ? uid : null;
}
