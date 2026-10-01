import {DiditApiError} from "../identity/didit/diditClient.js";
import {
  DiditImageRejectedError,
  type DiditFaceClient,
} from "../identity/didit/diditFaceClient.js";
import {
  FaceProviderError,
  type FaceMatchOutcome,
  type FaceVerificationProvider,
  type LivenessOutcome,
} from "./provider.js";

/** Didit's verdict word for a pass. Exact and case-sensitive, like diditStatusMapping. */
const APPROVED = "Approved";
const DECLINED = "Declined";

/**
 * Translates Didit's standalone biometric answers into MEVORA's closed words.
 *
 * Fails closed throughout: only the exact approval word passes, and a verdict
 * word this code does not know is an error, never a pass.
 */
export class DiditFaceProvider implements FaceVerificationProvider {
  readonly id = "didit";

  constructor(
    private readonly client: DiditFaceClient,
    private readonly thresholds: {liveness: number; match: number},
  ) {}

  async checkLiveness(selfie: Buffer): Promise<LivenessOutcome> {
    try {
      const result = await this.client.passiveLiveness({
        image: selfie,
        declineThreshold: this.thresholds.liveness,
      });
      if (result.status === APPROVED) {
        return "live";
      }
      if (result.status === DECLINED) {
        return result.risks.includes("NO_FACE_DETECTED") ? "no_face" : "not_live";
      }
      throw new FaceProviderError("didit-liveness-unknown-status", false);
    } catch (error) {
      if (error instanceof DiditImageRejectedError) {
        // Didit could not find a face to judge in what was sent.
        return "no_face";
      }
      throw translate(error);
    }
  }

  async matchFaces(selfie: Buffer, reference: Buffer): Promise<FaceMatchOutcome> {
    try {
      const result = await this.client.faceMatch({
        userImage: selfie,
        referenceImage: reference,
        declineThreshold: this.thresholds.match,
      });
      // More than one face in the profile photo: a match would not say which
      // of them is the member, so the photo cannot be an anchor either way.
      if (result.referenceFaceCount !== null && result.referenceFaceCount !== 1) {
        return "reference_unusable";
      }
      if (result.risks.includes("NO_REFERENCE_IMAGE")) {
        return "reference_unusable";
      }
      if (result.status === APPROVED) {
        return "match";
      }
      if (result.status === DECLINED) {
        return "no_match";
      }
      throw new FaceProviderError("didit-face-match-unknown-status", false);
    } catch (error) {
      if (error instanceof DiditImageRejectedError) {
        // Liveness already accepted the selfie, so the image Didit could not
        // use here is the profile photo.
        return "reference_unusable";
      }
      throw translate(error);
    }
  }
}

function translate(error: unknown): FaceProviderError {
  if (error instanceof FaceProviderError) {
    return error;
  }
  if (error instanceof DiditApiError) {
    // 401/403: bad credentials or exhausted credits. Nothing a retry fixes.
    const unavailable = error.statusCode === 401 || error.statusCode === 403;
    return new FaceProviderError(error.code, error.retryable, unavailable);
  }
  return new FaceProviderError("didit-face-unexpected", false);
}
