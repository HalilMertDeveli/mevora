import {
  FieldValue,
  Timestamp,
  getFirestore,
  type Firestore,
} from "firebase-admin/firestore";
import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";
import {JobStatus, type JobKind, type JobStatus as JobStatusType} from "./types.js";

export type JobRecord = {
  jobId: string;
  kind: JobKind | string;
  status: JobStatusType;
  idempotencyKey: string;
  attempts: number;
  maxAttempts: number;
  payload: Record<string, unknown>;
  error?: string | null;
  createdBy: string;
  requiresHumanReview: boolean;
};

const COLLECTION = "automationJobs";

export function jobRef(jobId: string, db: Firestore = getFirestore()) {
  return db.collection(COLLECTION).doc(jobId);
}

/**
 * Create or return an existing job for the same idempotency key.
 * Job document id == idempotencyKey so duplicates collapse.
 */
export async function enqueueJob(options: {
  kind: JobKind | string;
  idempotencyKey: string;
  payload?: Record<string, unknown>;
  createdBy: string;
  requiresHumanReview?: boolean;
  maxAttempts?: number;
  db?: Firestore;
}): Promise<{jobId: string; created: boolean; status: JobStatusType}> {
  const db = options.db ?? getFirestore();
  const jobId = options.idempotencyKey;
  const ref = jobRef(jobId, db);
  const existing = await ref.get();
  if (existing.exists) {
    const status = String(existing.data()?.status ?? JobStatus.queued) as JobStatusType;
    return {jobId, created: false, status};
  }
  await ref.set({
    jobId,
    kind: options.kind,
    status: options.requiresHumanReview ? JobStatus.manual_review : JobStatus.queued,
    idempotencyKey: options.idempotencyKey,
    attempts: 0,
    maxAttempts: options.maxAttempts ?? 5,
    payload: options.payload ?? {},
    error: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdBy: options.createdBy,
    requiresHumanReview: options.requiresHumanReview === true,
  });
  return {
    jobId,
    created: true,
    status: options.requiresHumanReview ? JobStatus.manual_review : JobStatus.queued,
  };
}

/** Atomically claim a queued/retrying job for execution. */
export async function claimJob(
  jobId: string,
  db: Firestore = getFirestore(),
): Promise<JobRecord | null> {
  return db.runTransaction(async (tx) => {
    const ref = jobRef(jobId, db);
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return null;
    }
    const data = snap.data()!;
    const status = String(data.status);
    if (status !== JobStatus.queued && status !== JobStatus.retrying) {
      return null;
    }
    if (data.requiresHumanReview === true && status !== JobStatus.retrying) {
      return null;
    }
    const attempts = Number(data.attempts ?? 0) + 1;
    tx.update(ref, {
      status: JobStatus.running,
      attempts,
      updatedAt: FieldValue.serverTimestamp(),
      claimedAt: FieldValue.serverTimestamp(),
    });
    return {
      jobId,
      kind: String(data.kind),
      status: JobStatus.running,
      idempotencyKey: String(data.idempotencyKey ?? jobId),
      attempts,
      maxAttempts: Number(data.maxAttempts ?? 5),
      payload: (data.payload as Record<string, unknown>) ?? {},
      error: null,
      createdBy: String(data.createdBy ?? "system"),
      requiresHumanReview: data.requiresHumanReview === true,
    };
  });
}

export async function completeJob(
  jobId: string,
  result: Record<string, unknown>,
  db: Firestore = getFirestore(),
): Promise<void> {
  await jobRef(jobId, db).set(
    {
      status: JobStatus.succeeded,
      result,
      error: null,
      updatedAt: FieldValue.serverTimestamp(),
      completedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

export async function failJob(
  jobId: string,
  error: string,
  options: {retry?: boolean; maxAttempts?: number; attempts?: number} = {},
  db: Firestore = getFirestore(),
): Promise<JobStatusType> {
  const attempts = options.attempts ?? 1;
  const maxAttempts = options.maxAttempts ?? 5;
  const shouldRetry = options.retry !== false && attempts < maxAttempts;
  const status = shouldRetry ? JobStatus.retrying : JobStatus.failed;
  await jobRef(jobId, db).set(
    {
      status,
      error: error.slice(0, 1000),
      updatedAt: FieldValue.serverTimestamp(),
      nextRetryAt: shouldRetry
        ? Timestamp.fromMillis(Date.now() + backoffMs(attempts))
        : null,
    },
    {merge: true},
  );
  return status;
}

export async function markManualReview(
  jobId: string,
  reason: string,
  db: Firestore = getFirestore(),
): Promise<void> {
  await jobRef(jobId, db).set(
    {
      status: JobStatus.manual_review,
      requiresHumanReview: true,
      error: reason.slice(0, 1000),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

function backoffMs(attempt: number): number {
  const base = Math.min(15 * 60 * 1000, 1000 * Math.pow(2, Math.max(0, attempt - 1)));
  return base;
}

/** Admin gate: custom claim `admin === true` only (never client-writable fields). */
export function requireAdmin(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  const claim = request.auth?.token?.admin;
  if (claim !== true) {
    throw new HttpsError("permission-denied", "admin-required");
  }
  return uid;
}

export function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}
