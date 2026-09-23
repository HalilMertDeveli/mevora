import type {VerificationStatus} from "../sumsub/sumsubStatus.js";
import type {IdentityVerificationStatus} from "./identityVerificationStatus.js";

/**
 * Translates the legacy Sumsub-shaped internal status into the
 * provider-neutral vocabulary.
 *
 * This exists so the neutral model can read the documents Sumsub wrote
 * without the domain learning Sumsub's names. Production currently holds no
 * such documents (STEP 14: 0 verification docs, 0 verified users), so this is
 * a correctness guarantee rather than a live migration path — but the
 * translation is cheap and keeps the cutover reversible.
 */
const SUMSUB_TO_NEUTRAL: Record<VerificationStatus, IdentityVerificationStatus> = {
  not_started: "not_started",
  started: "in_progress",
  pending: "in_review",
  approved: "verified",
  rejected: "declined",
  // Sumsub's "retry" reject type means the user may resubmit, which is the
  // same affordance as an expired session: start again, not a final decline.
  retry_required: "expired",
};

export function mapLegacySumsubStatus(raw: unknown): IdentityVerificationStatus {
  if (typeof raw !== "string" || raw.length === 0) {
    return "not_started";
  }
  const mapped = SUMSUB_TO_NEUTRAL[raw as VerificationStatus];
  return mapped ?? "error";
}
