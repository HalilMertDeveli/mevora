import {randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import type {Bucket} from "@google-cloud/storage";
import {diditApiKey} from "../identity/didit/diditConfig.js";
import {processPendingProfilePhoto} from "../moderation/photoModerationService.js";
import {resolveDailyGlobalCap} from "./faceAnchorConfig.js";
import {SUBMIT_TIMEOUT_SECONDS} from "./faceAnchorRecord.js";
import {
  startFaceAnchorVerification as start,
  submitFaceAnchorVerification as submit,
  sweepFaceAnchorSelfies,
  type FaceAnchorBucket,
  type FaceAnchorDeps,
} from "./faceAnchorService.js";
import {normalizeForVerification} from "./images.js";
import {resolveFaceVerificationProvider} from "./resolveProvider.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

/** Old enough that the upload trigger has had its chance. */
const TRIGGER_GRACE_MS = 20 * 1000;
const PENDING_EXTENSION = /\.(jpg|jpeg|png|webp)$/i;

/**
 * Moderates a photo whose Storage trigger never ran. The trigger is retried
 * only once a day; a new member waiting to verify their first photo should
 * not be held up by a missed event.
 */
async function moderatePending(uid: string, imageId: string): Promise<void> {
  try {
    const bucket = getStorage().bucket();
    const prefix = `users/${uid}/profile/pending/${imageId}`;
    const [files] = await bucket.getFiles({prefix, maxResults: 5, autoPaginate: false});
    const file = files.find((candidate) =>
      candidate.name === prefix ||
      (candidate.name.startsWith(`${prefix}.`) && PENDING_EXTENSION.test(candidate.name)));
    if (!file) {
      return;
    }
    const [metadata] = await file.getMetadata();
    const created = Date.parse(String(metadata.timeCreated ?? ""));
    if (Number.isNaN(created) || Date.now() - created < TRIGGER_GRACE_MS) {
      return;
    }
    await processPendingProfilePhoto({
      db,
      bucket: bucket as Bucket,
      uid,
      imageId,
      pendingPath: file.name,
      contentType: metadata.contentType,
      sizeBytes: Number(metadata.size ?? 0),
    });
  } catch (error) {
    logger.warn("face anchor: inline moderation skipped", {
      error: error instanceof Error ? error.name : "unknown",
    });
  }
}

function deps(): FaceAnchorDeps {
  return {
    db,
    bucket: () => getStorage().bucket() as unknown as FaceAnchorBucket,
    provider: () => resolveFaceVerificationProvider(db),
    now: () => Date.now(),
    newAttemptId: () => randomUUID(),
    normalizeImage: normalizeForVerification,
    dailyGlobalCap: resolveDailyGlobalCap,
    moderatePending,
  };
}

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function payload(request: CallableRequest): Record<string, unknown> {
  const data = request.data;
  return data && typeof data === "object" ? (data as Record<string, unknown>) : {};
}

// Only the API key: these callables have no use for the webhook signing secret.
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
  secrets: [diditApiKey],
};

/**
 * Opens a verification attempt for one of the caller's approved photos.
 *
 * Reads `photoId` and `consentVersion` from the request and nothing else: the
 * uid comes from the auth context, and there is no field that selects a
 * provider, a test mode or an outcome.
 */
export const startFaceAnchorVerification = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const data = payload(request);
  return start(deps(), uid, {photoId: data.photoId, consentVersion: data.consentVersion});
});

/** Runs liveness and the 1:1 face match for an attempt whose selfie is uploaded. */
export const submitFaceAnchorVerification = onCall(
  {...callableOptions, timeoutSeconds: SUBMIT_TIMEOUT_SECONDS, memory: "512MiB"},
  async (request) => {
    const uid = requireUid(request);
    return submit(deps(), uid, {attemptId: payload(request).attemptId});
  },
);

/** Removes verification selfies that outlived their attempt. */
export const faceAnchorSelfieSweep = onSchedule(
  {schedule: "every 15 minutes", region: "europe-west1"},
  async () => {
    const result = await sweepFaceAnchorSelfies(deps());
    if (result.deleted > 0) {
      logger.info("face anchor: stale selfies removed", result);
    }
  },
);
