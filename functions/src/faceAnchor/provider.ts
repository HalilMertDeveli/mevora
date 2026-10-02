/**
 * The seam between MEVORA's Face Anchor pipeline and whoever answers the two
 * biometric questions.
 *
 * Every answer is a closed word. No score, no confidence, no face geometry and
 * no provider payload crosses this interface — the pipeline cannot store or log
 * what it is never handed.
 */

/** Is the selfie a live person in front of the camera? */
export type LivenessOutcome = "live" | "not_live" | "no_face";

/**
 * Is the selfie the person in the profile photo?
 *
 * `reference_unusable`: the profile photo cannot carry a verdict — no face in
 * it, or more than one, so a match would not say which person is the member.
 */
export type FaceMatchOutcome = "match" | "no_match" | "reference_unusable";

export interface FaceVerificationProvider {
  /** Stored on the ledger verdict. Not a secret, not a request id. */
  readonly id: string;
  /** Both images are JPEG bytes, already stripped of metadata. */
  checkLiveness(selfie: Buffer): Promise<LivenessOutcome>;
  matchFaces(selfie: Buffer, reference: Buffer): Promise<FaceMatchOutcome>;
}

/**
 * The provider did not answer the question.
 *
 * `retryable`: an outage or a timeout — nothing was decided, and the member is
 * not charged an attempt. `unavailable`: the integration itself is not usable
 * (credentials, credits); retrying will not help and someone must be told.
 */
export class FaceProviderError extends Error {
  constructor(
    readonly code: string,
    readonly retryable: boolean,
    readonly unavailable = false,
  ) {
    super(code);
    this.name = "FaceProviderError";
  }
}
