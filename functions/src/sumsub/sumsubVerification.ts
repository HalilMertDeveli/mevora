import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import type {VerificationStatus} from "./sumsubStatus.js";

export const VERIFICATION_DOC_ID = "sumsub";
export const COOLDOWN_MS = 15 * 60 * 1000;
export const MAX_ATTEMPTS_PER_DAY = 5;

export type VerificationRecord = {
  verificationStatus: VerificationStatus;
  verificationLevel?: string;
  sumsubApplicantId?: string;
  verificationUpdatedAt?: Timestamp;
  verifiedAt?: Timestamp;
  verificationAttemptCount?: number;
  lastVerificationAttemptAt?: Timestamp;
  lastWebhookType?: string;
  lastWebhookAt?: Timestamp;
  lastWebhookCorrelationId?: string;
};

export function verificationRef(db: Firestore, uid: string) {
  return db.doc(`users/${uid}/verification/${VERIFICATION_DOC_ID}`);
}

export function parseVerificationRecord(data: Record<string, unknown> | undefined): VerificationRecord {
  if (!data) {
    return {verificationStatus: "not_started"};
  }
  return {
    verificationStatus: (data.verificationStatus as VerificationStatus) ?? "not_started",
    verificationLevel: data.verificationLevel as string | undefined,
    sumsubApplicantId: data.sumsubApplicantId as string | undefined,
    verificationUpdatedAt: data.verificationUpdatedAt as Timestamp | undefined,
    verifiedAt: data.verifiedAt as Timestamp | undefined,
    verificationAttemptCount: typeof data.verificationAttemptCount === "number"
      ? data.verificationAttemptCount
      : undefined,
    lastVerificationAttemptAt: data.lastVerificationAttemptAt as Timestamp | undefined,
    lastWebhookType: data.lastWebhookType as string | undefined,
    lastWebhookAt: data.lastWebhookAt as Timestamp | undefined,
    lastWebhookCorrelationId: data.lastWebhookCorrelationId as string | undefined,
  };
}

export function cooldownRemainingMs(record: VerificationRecord, nowMs: number): number {
  const last = record.lastVerificationAttemptAt?.toMillis();
  if (!last) {
    return 0;
  }
  const elapsed = nowMs - last;
  return elapsed >= COOLDOWN_MS ? 0 : COOLDOWN_MS - elapsed;
}

export function canStartVerification(record: VerificationRecord, nowMs: number): {
  allowed: boolean;
  reason?: "cooldown" | "already_verified" | "attempt_limit";
  retryAfterSeconds?: number;
} {
  if (record.verificationStatus === "approved") {
    return {allowed: false, reason: "already_verified"};
  }
  const remaining = cooldownRemainingMs(record, nowMs);
  if (remaining > 0) {
    return {
      allowed: false,
      reason: "cooldown",
      retryAfterSeconds: Math.ceil(remaining / 1000),
    };
  }
  const lastAttempt = record.lastVerificationAttemptAt?.toMillis() ?? 0;
  const dayAgo = nowMs - 24 * 60 * 60 * 1000;
  const attempts = record.verificationAttemptCount ?? 0;
  if (lastAttempt >= dayAgo && attempts >= MAX_ATTEMPTS_PER_DAY) {
    return {allowed: false, reason: "attempt_limit"};
  }
  return {allowed: true};
}

export async function markVerificationStarted(
  db: Firestore,
  uid: string,
  levelName: string,
): Promise<void> {
  const ref = verificationRef(db, uid);
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = parseVerificationRecord(snap.data());
    const gate = canStartVerification(existing, Date.now());
    if (!gate.allowed) {
      throw new VerificationGateError(gate.reason ?? "blocked", gate.retryAfterSeconds);
    }
    const lastAttempt = existing.lastVerificationAttemptAt?.toMillis() ?? 0;
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const nextCount = lastAttempt >= dayAgo
      ? (existing.verificationAttemptCount ?? 0) + 1
      : 1;
    tx.set(
      ref,
      {
        verificationStatus: "started" as const,
        verificationLevel: levelName,
        verificationUpdatedAt: now,
        lastVerificationAttemptAt: now,
        verificationAttemptCount: nextCount,
      },
      {merge: true},
    );
  });
}

export class VerificationGateError extends Error {
  constructor(
    readonly reason: "cooldown" | "already_verified" | "attempt_limit" | "blocked",
    readonly retryAfterSeconds?: number,
  ) {
    super(reason);
    this.name = "VerificationGateError";
  }
}
