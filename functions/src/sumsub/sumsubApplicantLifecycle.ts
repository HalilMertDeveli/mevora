import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {SumsubApiError, SumsubClient} from "./sumsubClient.js";
import {resolveSumsubConfig} from "./sumsubConfig.js";
import type {SumsubHttpMethod} from "./sumsubAuth.js";

/**
 * Sumsub applicant data lifecycle.
 *
 * Firestore verification docs are removed by deleteUserAccount. The Sumsub
 * side needs its own API calls, and Sumsub publishes exactly two relevant
 * operations:
 *
 *   POST  /resources/applicants/{applicantId}/reset
 *         Clears the collected verification data and returns the applicant to
 *         its initial state. Responds `{"ok": 1}`.
 *
 *   PATCH /resources/applicants/{applicantId}/presence/deactivated
 *         Marks the profile so it behaves "as if it never existed": no
 *         operator can act on it and it is ignored for duplicate checks.
 *         Rejected while the applicant review status is pending, queued or
 *         prechecked.
 *
 * Sumsub does NOT publish a permanent-erasure endpoint. Full GDPR erasure of
 * an applicant is a manual request to Sumsub support and cannot be automated
 * from here — see docs/SUMSUB_SETUP.md.
 *
 * Everything below is best effort by design: account deletion must never fail
 * because an external applicant is already gone, is mid-review, or because
 * Sumsub is unreachable.
 */

/** Sumsub applicant ids are 24 lowercase hex-ish characters. */
const APPLICANT_ID_PATTERN = /^[0-9a-zA-Z]{24}$/;

/** The slice of SumsubClient this module needs, so tests can stub the boundary. */
export type SumsubApplicantApi = {
  request<T>(
    method: SumsubHttpMethod,
    pathWithQuery: string,
    body?: unknown,
  ): Promise<T>;
};

export type SumsubLifecycleOutcome =
  | "no-applicant"
  | "invalid-applicant-id"
  | "not-configured"
  | "reset-and-deactivated"
  | "reset-only"
  | "already-absent"
  | "remote-failure";

/**
 * Resets and deactivates the Sumsub applicant tied to a deleted account.
 *
 * Never throws and never rejects: the return value reports what happened so
 * the caller can log it. A 400/404 from Sumsub means the applicant is already
 * gone, which is success for our purposes.
 */
export async function requestSumsubApplicantDeletion(input: {
  uid: string;
  applicantId?: string;
  client?: SumsubApplicantApi;
}): Promise<SumsubLifecycleOutcome> {
  const applicantId = input.applicantId?.trim();
  if (!applicantId) {
    return "no-applicant";
  }
  if (!APPLICANT_ID_PATTERN.test(applicantId)) {
    // Never interpolate an unvalidated value into an API path.
    logger.warn(
      "Sumsub applicant cleanup skipped: malformed applicant id",
      safeLogMeta({uid: input.uid}),
    );
    return "invalid-applicant-id";
  }

  const client = input.client ?? createClient();
  if (!client) {
    return "not-configured";
  }

  const encodedId = encodeURIComponent(applicantId);

  const reset = await call(
    client,
    "POST",
    `/resources/applicants/${encodedId}/reset`,
    input.uid,
    "reset",
  );
  if (reset === "absent") {
    return "already-absent";
  }
  if (reset === "failed") {
    return "remote-failure";
  }

  const deactivate = await call(
    client,
    "PATCH",
    `/resources/applicants/${encodedId}/presence/deactivated`,
    input.uid,
    "deactivate",
  );
  if (deactivate === "ok") {
    return "reset-and-deactivated";
  }
  if (deactivate === "absent") {
    return "already-absent";
  }
  // The verification data is already cleared; deactivation can be refused
  // while a review is pending. That is not a deletion failure.
  return "reset-only";
}

type CallResult = "ok" | "absent" | "failed";

async function call(
  client: SumsubApplicantApi,
  method: SumsubHttpMethod,
  path: string,
  uid: string,
  step: string,
): Promise<CallResult> {
  try {
    await client.request<unknown>(method, path);
    return "ok";
  } catch (error) {
    if (error instanceof SumsubApiError) {
      // 400 is what Sumsub answers for an id it does not know; 404 covers a
      // removed applicant. Both mean there is nothing left to clean up.
      if (error.statusCode === 400 || error.statusCode === 404) {
        return "absent";
      }
      logger.warn(
        "Sumsub applicant cleanup rejected",
        // No applicant id, no response body: both can carry KYC identifiers.
        safeLogMeta({uid, step, status: error.statusCode, code: error.code}),
      );
      return "failed";
    }
    logger.warn(
      "Sumsub applicant cleanup call failed",
      safeLogMeta({uid, step, error: String(error)}),
    );
    return "failed";
  }
}

function createClient(): SumsubApplicantApi | null {
  const config = resolveSumsubConfig();
  if (!config) {
    return null;
  }
  return new SumsubClient(config.appToken, config.secretKey, config.baseUrl);
}
