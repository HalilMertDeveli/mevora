/**
 * Face Anchor verification attempt — document model and the pure rules over it.
 *
 * One document per member, users/{uid}/faceAnchor/state, owner-readable and
 * never client-writable. It holds the *current* attempt only (so nothing
 * accumulates) and the member's attempt budget.
 *
 * What is deliberately not here, or anywhere else in MEVORA: the selfie, a
 * similarity or liveness score, a face embedding or landmarks, the provider's
 * response or request id. The verdict itself lives on the photo's moderation
 * ledger entry; this document is only the attempt's progress.
 */

export const FACE_ANCHOR_SCHEMA_VERSION = 1;

/** The consent text the member agreed to. Bump when the wording's meaning changes. */
export const FACE_ANCHOR_CONSENT_VERSION = 1;

/** How long a member has to capture and upload the selfie. */
export const ATTEMPT_TTL_MS = 10 * 60 * 1000;

/**
 * One clock for the whole pipeline. A provider call may take at most
 * PROVIDER_TIMEOUT_MS; three of them (liveness, match, one match retry) fit
 * inside the callable's timeout, and the callable's timeout fits inside
 * PROCESSING_STALE_MS. So an attempt still `processing` after
 * PROCESSING_STALE_MS belongs to an invocation that is already dead.
 */
export const PROVIDER_TIMEOUT_MS = 15 * 1000;
export const SUBMIT_TIMEOUT_SECONDS = 60;
export const PROCESSING_STALE_MS = 90 * 1000;

/** A selfie older than this is deleted by the sweep, whatever state it is in. */
export const SELFIE_MAX_AGE_MS = 15 * 60 * 1000;

export const BUDGET_WINDOW_MS = 24 * 60 * 60 * 1000;
export const MAX_ATTEMPTS_PER_WINDOW = 5;
export const MAX_REFUNDS_PER_WINDOW = 2;
export const COOLDOWN_MS = 20 * 1000;

export const MAX_SELFIE_BYTES = 5 * 1024 * 1024;

export const FACE_ANCHOR_STATUSES = [
  "awaiting_selfie",
  "processing",
  "verified",
  "failed",
  "expired",
  "error",
] as const;
export type FaceAnchorStatus = (typeof FACE_ANCHOR_STATUSES)[number];

/**
 * Why an attempt did not verify. Coarse on purpose: enough to tell the member
 * what to do next, nothing a provider said verbatim.
 */
export const FACE_ANCHOR_REASONS = [
  "liveness_failed",
  "face_mismatch",
  "photo_face_unclear",
  "selfie_invalid",
  "technical_error",
] as const;
export type FaceAnchorReason = (typeof FACE_ANCHOR_REASONS)[number];

export type FaceAnchorStateDoc = {
  schemaVersion: number;
  attemptId: string | null;
  photoId: string | null;
  status: FaceAnchorStatus | "none";
  reason: FaceAnchorReason | null;
  expiresAtMs: number;
  processingStartedAtMs: number;
  windowStartedAtMs: number;
  attemptCount: number;
  refundCount: number;
  lastAttemptAtMs: number;
};

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export function parseFaceAnchorState(data: Record<string, unknown> | undefined): FaceAnchorStateDoc {
  const status = (FACE_ANCHOR_STATUSES as readonly string[]).includes(String(data?.status))
    ? (data?.status as FaceAnchorStatus)
    : "none";
  const reason = (FACE_ANCHOR_REASONS as readonly string[]).includes(String(data?.reason))
    ? (data?.reason as FaceAnchorReason)
    : null;
  return {
    schemaVersion: num(data?.schemaVersion),
    attemptId: typeof data?.attemptId === "string" && data.attemptId ? data.attemptId : null,
    photoId: typeof data?.photoId === "string" && data.photoId ? data.photoId : null,
    status,
    reason,
    expiresAtMs: num(data?.expiresAtMs),
    processingStartedAtMs: num(data?.processingStartedAtMs),
    windowStartedAtMs: num(data?.windowStartedAtMs),
    attemptCount: num(data?.attemptCount),
    refundCount: num(data?.refundCount),
    lastAttemptAtMs: num(data?.lastAttemptAtMs),
  };
}

export function isTerminal(status: FaceAnchorStateDoc["status"]): boolean {
  return status === "verified" || status === "failed" || status === "expired" || status === "error";
}

/** An attempt whose invocation can still be running. */
export function isProcessingFresh(state: FaceAnchorStateDoc, nowMs: number): boolean {
  return state.status === "processing" && nowMs - state.processingStartedAtMs < PROCESSING_STALE_MS;
}

export type BudgetDecision =
  | {allowed: true; windowStartedAtMs: number; attemptCount: number; refundCount: number}
  | {allowed: false; reason: "cooldown" | "attempt_limit"; retryAfterSeconds: number};

/**
 * Whether one more billed verification may run now, and the counters if so.
 *
 * Spent when a submission starts processing — that is the moment the provider
 * is about to be paid — not when an attempt is opened, so opening and
 * abandoning attempts costs nothing and locks nobody out.
 */
export function budgetDecision(state: FaceAnchorStateDoc, nowMs: number): BudgetDecision {
  const sinceLast = nowMs - state.lastAttemptAtMs;
  if (state.lastAttemptAtMs > 0 && sinceLast < COOLDOWN_MS) {
    return {
      allowed: false,
      reason: "cooldown",
      retryAfterSeconds: Math.ceil((COOLDOWN_MS - sinceLast) / 1000),
    };
  }
  const windowOpen = state.windowStartedAtMs > 0 && nowMs - state.windowStartedAtMs < BUDGET_WINDOW_MS;
  if (!windowOpen) {
    return {allowed: true, windowStartedAtMs: nowMs, attemptCount: 1, refundCount: 0};
  }
  if (state.attemptCount >= MAX_ATTEMPTS_PER_WINDOW) {
    return {
      allowed: false,
      reason: "attempt_limit",
      retryAfterSeconds: Math.ceil((state.windowStartedAtMs + BUDGET_WINDOW_MS - nowMs) / 1000),
    };
  }
  return {
    allowed: true,
    windowStartedAtMs: state.windowStartedAtMs,
    attemptCount: state.attemptCount + 1,
    refundCount: state.refundCount,
  };
}

/**
 * The counters after an attempt that the provider never answered.
 *
 * Only a provider outage is refunded — a decline was billed and stays spent —
 * and only so many times per window, so "make the provider time out" is not a
 * way to an unlimited budget. The cooldown is never refunded.
 */
export function refundedCounters(state: FaceAnchorStateDoc): {attemptCount: number; refundCount: number} {
  if (state.refundCount >= MAX_REFUNDS_PER_WINDOW || state.attemptCount <= 0) {
    return {attemptCount: state.attemptCount, refundCount: state.refundCount};
  }
  return {attemptCount: state.attemptCount - 1, refundCount: state.refundCount + 1};
}

export function faceAnchorStatePath(uid: string): string {
  return `users/${uid}/faceAnchor/state`;
}

export const SELFIE_PREFIX = "face-anchor/pending/";

/**
 * Where the temporary selfie lives. Outside every profile-photo prefix, and
 * outside users/{uid}/ so one prefix listing finds every stale selfie.
 */
export function selfiePath(uid: string, attemptId: string): string {
  return `${SELFIE_PREFIX}${uid}/${attemptId}`;
}

export function parseSelfiePath(name: string): {uid: string; attemptId: string} | null {
  const match = name.match(/^face-anchor\/pending\/([^/]+)\/([^/]+)$/);
  return match ? {uid: match[1], attemptId: match[2]} : null;
}

/** UTC day key for the global spend counter. */
export function usageDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}
