import type {Timestamp} from "firebase-admin/firestore";
import type {IdentityVerificationReasonCode} from "./identityVerificationProvider.js";
import {
  type IdentityVerificationProvider,
  type IdentityVerificationStatus,
  parseIdentityVerificationStatus,
} from "./identityVerificationStatus.js";

/**
 * The verification document MEVORA owns, and the gates around starting a new
 * session.
 *
 * This is deliberately the *whole* footprint of identity verification in
 * Firestore: one document per user at `users/{uid}/verification/identity`. A
 * single document is what makes account deletion provably complete — there is
 * no second place for verification state to hide.
 *
 * Absent by design: document images, selfies, liveness video, document
 * numbers, provider report bodies and raw webhook payloads.
 */

/** Bumped only when the document's shape changes in a way readers must know. */
export const IDENTITY_VERIFICATION_SCHEMA_VERSION = 1;

export const IDENTITY_COOLDOWN_MS = 15 * 60 * 1000;
export const IDENTITY_MAX_ATTEMPTS_PER_DAY = 5;

export type IdentityVerificationDoc = {
  schemaVersion: number;
  provider: IdentityVerificationProvider;
  providerSessionId?: string;
  status: IdentityVerificationStatus;
  reason?: IdentityVerificationReasonCode;
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
  verifiedAt?: Timestamp;
  attemptCount: number;
  lastAttemptAt?: Timestamp;
  /** Idempotency key of the last webhook applied. */
  lastEventId?: string;
  /** Ordering key of the last webhook applied, in epoch ms. */
  lastEventAtMs?: number;
};

const REASON_CODES: readonly IdentityVerificationReasonCode[] = [
  "document_unreadable",
  "document_unsupported",
  "liveness_failed",
  "face_mismatch",
  "manual_review",
  "provider_error",
] as const;

function parseReason(raw: unknown): IdentityVerificationReasonCode | undefined {
  const value = typeof raw === "string" ? raw : "";
  return (REASON_CODES as readonly string[]).includes(value)
    ? (value as IdentityVerificationReasonCode)
    : undefined;
}

function parseProvider(raw: unknown): IdentityVerificationProvider {
  return raw === "sumsub" ? "sumsub" : "didit";
}

export function parseIdentityVerificationDoc(
  data: Record<string, unknown> | undefined,
): IdentityVerificationDoc {
  if (!data) {
    return {
      schemaVersion: IDENTITY_VERIFICATION_SCHEMA_VERSION,
      provider: "didit",
      status: "not_started",
      attemptCount: 0,
    };
  }
  return {
    schemaVersion: typeof data.schemaVersion === "number" ? data.schemaVersion : 0,
    provider: parseProvider(data.provider),
    providerSessionId: typeof data.providerSessionId === "string"
      ? data.providerSessionId
      : undefined,
    status: parseIdentityVerificationStatus(data.status),
    reason: parseReason(data.reason),
    createdAt: data.createdAt as Timestamp | undefined,
    updatedAt: data.updatedAt as Timestamp | undefined,
    verifiedAt: data.verifiedAt as Timestamp | undefined,
    attemptCount: typeof data.attemptCount === "number" ? data.attemptCount : 0,
    lastAttemptAt: data.lastAttemptAt as Timestamp | undefined,
    lastEventId: typeof data.lastEventId === "string" ? data.lastEventId : undefined,
    lastEventAtMs: typeof data.lastEventAtMs === "number" ? data.lastEventAtMs : undefined,
  };
}

export type StartBlockReason = "already_verified" | "in_flight" | "cooldown" | "attempt_limit";

export type StartGate = {
  allowed: boolean;
  reason?: StartBlockReason;
  retryAfterSeconds?: number;
};

/**
 * Whether a new session may be created right now.
 *
 * Mirrored client-side for messaging only; this is the enforcer. The in-flight
 * check is what stops a user spawning parallel provider sessions by tapping
 * twice.
 */
export function canStartIdentitySession(
  doc: IdentityVerificationDoc,
  nowMs: number,
): StartGate {
  if (doc.status === "verified") {
    return {allowed: false, reason: "already_verified"};
  }
  if (doc.status === "pending" || doc.status === "in_progress" || doc.status === "in_review") {
    return {allowed: false, reason: "in_flight"};
  }
  const last = doc.lastAttemptAt?.toMillis();
  if (last === undefined) {
    return {allowed: true};
  }
  const elapsed = nowMs - last;
  if (elapsed < IDENTITY_COOLDOWN_MS) {
    return {
      allowed: false,
      reason: "cooldown",
      retryAfterSeconds: Math.ceil((IDENTITY_COOLDOWN_MS - elapsed) / 1000),
    };
  }
  const withinDay = elapsed < 24 * 60 * 60 * 1000;
  if (withinDay && doc.attemptCount >= IDENTITY_MAX_ATTEMPTS_PER_DAY) {
    return {allowed: false, reason: "attempt_limit"};
  }
  return {allowed: true};
}

/**
 * Whether an inbound provider event should be applied.
 *
 * Two independent guards, because providers redeliver and reorder:
 *
 *  - the same `eventId` twice is a duplicate and is ignored;
 *  - an event older than the one already applied is stale and is ignored,
 *    so a late "In Progress" cannot walk a user back out of `verified`.
 *
 * An event carrying no ordering information is applied only when the document
 * has none either — otherwise it cannot be proven newer, and the safe answer
 * to "is this newer?" is no.
 */
export function shouldApplyEvent(
  doc: IdentityVerificationDoc,
  event: {eventId: string; occurredAtMs?: number},
): {apply: boolean; skipReason?: "duplicate" | "stale"} {
  if (doc.lastEventId && doc.lastEventId === event.eventId) {
    return {apply: false, skipReason: "duplicate"};
  }
  const applied = doc.lastEventAtMs;
  if (applied === undefined) {
    return {apply: true};
  }
  if (event.occurredAtMs === undefined) {
    return {apply: false, skipReason: "stale"};
  }
  if (event.occurredAtMs < applied) {
    return {apply: false, skipReason: "stale"};
  }
  return {apply: true};
}
