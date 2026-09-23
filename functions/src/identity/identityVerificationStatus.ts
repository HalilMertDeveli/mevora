/**
 * Provider-neutral identity verification vocabulary.
 *
 * MEVORA's domain must not name its identity provider. Sumsub's review
 * answers and Didit's session statuses are both provider dialects; they are
 * translated into this vocabulary at the infrastructure boundary
 * (`sumsubStatusBridge.ts`, `diditStatusMapping.ts`) and nowhere else.
 *
 * Wire format is snake_case to match the existing verification document and
 * `profileVerificationStatusFromFirestore` on the Flutter side.
 */
export type IdentityVerificationProvider = "sumsub" | "didit";

export type IdentityVerificationStatus =
  | "not_started"
  | "in_progress"
  | "in_review"
  | "verified"
  | "declined"
  | "expired"
  | "error";

export const IDENTITY_VERIFICATION_STATUSES: readonly IdentityVerificationStatus[] = [
  "not_started",
  "in_progress",
  "in_review",
  "verified",
  "declined",
  "expired",
  "error",
] as const;

/**
 * The single predicate that may grant the verified badge. Nothing else —
 * not an SDK completion callback, not a client write — is allowed to decide
 * this. See `docs/DIDIT_MIGRATION_PHASE1.md` (STEP 12).
 */
export function grantsVerifiedBadge(status: IdentityVerificationStatus): boolean {
  return status === "verified";
}

/** No further provider transition is expected without a new session. */
export function isTerminalIdentityStatus(status: IdentityVerificationStatus): boolean {
  return status === "verified" || status === "declined" || status === "expired";
}

/** The user may start a new verification session from this state. */
export function canStartIdentityVerification(status: IdentityVerificationStatus): boolean {
  return status !== "verified" && status !== "in_review" && status !== "in_progress";
}

/**
 * Narrows unknown Firestore/webhook input.
 *
 * An absent field means the user has not started — that is the legitimate
 * initial state. Anything present but unrecognised (a stale provider enum, a
 * non-string, a value MEVORA has not reviewed) degrades to `error` rather
 * than to a status that could be read as progress.
 */
export function parseIdentityVerificationStatus(raw: unknown): IdentityVerificationStatus {
  if (raw === undefined || raw === null || raw === "") {
    return "not_started";
  }
  if (typeof raw !== "string") {
    return "error";
  }
  return (IDENTITY_VERIFICATION_STATUSES as readonly string[]).includes(raw)
    ? (raw as IdentityVerificationStatus)
    : "error";
}

/**
 * Provider-neutral verification document path.
 *
 * The live document is `users/{uid}/verification/sumsub` (STEP 4). Phase 2
 * writes `users/{uid}/verification/identity` instead; this helper exists so
 * the path is named once rather than in every call site.
 */
export const IDENTITY_VERIFICATION_DOC_ID = "identity";

export function identityVerificationDocPath(uid: string): string {
  return `users/${uid}/verification/${IDENTITY_VERIFICATION_DOC_ID}`;
}

/**
 * The minimum metadata MEVORA stores (STEP 6). Document images, selfies,
 * liveness video, ID numbers and raw webhook payloads are deliberately absent
 * and must stay absent: they live with the provider, never in Firestore.
 */
export type IdentityVerificationRecord = {
  provider: IdentityVerificationProvider;
  providerSessionId?: string;
  status: IdentityVerificationStatus;
  createdAt?: unknown;
  updatedAt?: unknown;
  verifiedAt?: unknown;
};
