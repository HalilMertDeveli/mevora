import {HttpsError, type FunctionsErrorCode} from "firebase-functions/v2/https";

/**
 * Domain error codes the admin platform returns.
 *
 * The admin web maps these to human messages. Raw Firestore / Auth errors are
 * never forwarded: anything that is not an AdminError becomes `internal_error`
 * with the detail kept in the server log only.
 */
export const ADMIN_ERROR_CODES = {
  unauthenticated: "unauthenticated",
  permission_denied: "permission-denied",
  mfa_required: "permission-denied",
  session_revoked: "unauthenticated",
  staff_inactive: "permission-denied",
  invalid_argument: "invalid-argument",
  not_found: "not-found",
  rate_limited: "resource-exhausted",
  case_already_assigned: "failed-precondition",
  case_not_assigned_to_you: "failed-precondition",
  invalid_state_transition: "failed-precondition",
  user_already_banned: "failed-precondition",
  user_already_suspended: "failed-precondition",
  user_not_restricted: "failed-precondition",
  user_deleted: "failed-precondition",
  cannot_modify_self: "failed-precondition",
  cannot_modify_super_admin: "failed-precondition",
  cannot_modify_staff: "failed-precondition",
  last_super_admin: "failed-precondition",
  role_grant_forbidden: "permission-denied",
  photo_already_reviewed: "failed-precondition",
  photo_review_in_progress: "aborted",
  appeal_already_resolved: "failed-precondition",
  appeal_not_allowed: "failed-precondition",
  appeal_window_closed: "failed-precondition",
  appeal_self_review: "failed-precondition",
  unsupported_job_action: "failed-precondition",
  ticket_closed: "failed-precondition",
  verification_override_forbidden: "permission-denied",
  conflict: "aborted",
  internal_error: "internal",
} as const satisfies Record<string, FunctionsErrorCode>;

export type AdminErrorCode = keyof typeof ADMIN_ERROR_CODES;

export class AdminError extends Error {
  constructor(
    readonly code: AdminErrorCode,
    message?: string,
    readonly detail?: Record<string, unknown>,
  ) {
    super(message ?? code);
    this.name = "AdminError";
  }
}

/** Converts a domain error to the callable wire format. */
export function toHttpsError(error: AdminError, requestId: string): HttpsError {
  return new HttpsError(ADMIN_ERROR_CODES[error.code], error.code, {
    code: error.code,
    requestId,
    ...(error.detail ?? {}),
  });
}
