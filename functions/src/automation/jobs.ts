import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";
import {JobKind, JobStatus, type JobKindValue, type JobStatusValue} from "./types.js";

const COLLECTION = "automationJobs";

export function jobRef(jobId: string, db: Firestore = getFirestore()) {
  return db.collection(COLLECTION).doc(jobId);
}

export type EnqueueJobOptions = {
  kind: JobKindValue | string;
  idempotencyKey: string;
  payload?: DocumentData;
  createdBy: string;
  maxAttempts?: number;
  requiresHumanReview?: boolean;
  db?: Firestore;
};

/**
 * Create or return an existing job for the same idempotency key.
 * Job document id == idempotencyKey so duplicates collapse.
 */
export async function enqueueJob(options: EnqueueJobOptions): Promise<{
  jobId: string;
  created: boolean;
  status: string;
}> {
  const db = options.db ?? getFirestore();
  const jobId = options.idempotencyKey;
  const ref = jobRef(jobId, db);
  const existing = await ref.get();
  if (existing.exists) {
    const status = String(existing.data()?.status ?? JobStatus.queued);
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

/**
 * Return a job that already reached a terminal state to `queued` with a fresh
 * payload and retry budget.
 *
 * Needed because job ids collapse on the idempotency key: a second deletion pass
 * for the same uid finds the first pass's job and would otherwise inherit its
 * verdict, which described the state *before* this pass ran. Jobs still queued,
 * running or awaiting human review are left alone.
 */
export async function rearmTerminalJob(
  jobId: string,
  payload: DocumentData,
  db: Firestore = getFirestore(),
): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const ref = jobRef(jobId, db);
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return false;
    }
    const status = String(snap.data()?.status);
    if (status !== JobStatus.succeeded && status !== JobStatus.failed) {
      return false;
    }
    tx.update(ref, {
      status: JobStatus.queued,
      attempts: 0,
      payload,
      error: null,
      result: null,
      nextRetryAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/** Atomically claim a queued/retrying job for execution. */
export async function claimJob(jobId: string, db: Firestore = getFirestore()) {
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
      status: JobStatus.running as JobStatusValue,
      idempotencyKey: String(data.idempotencyKey ?? jobId),
      attempts,
      maxAttempts: Number(data.maxAttempts ?? 5),
      payload: (data.payload ?? {}) as DocumentData,
      error: null as string | null,
      createdBy: String(data.createdBy ?? "system"),
      requiresHumanReview: data.requiresHumanReview === true,
    };
  });
}

export async function completeJob(
  jobId: string,
  result: DocumentData,
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
  options: {attempts?: number; maxAttempts?: number; retry?: boolean} = {},
  db: Firestore = getFirestore(),
): Promise<string> {
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

export {JobKind, JobStatus};
