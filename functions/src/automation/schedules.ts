import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {logger} from "firebase-functions";
import {enqueueJob} from "./jobs.js";
import {JobKind, ReviewQueueStatus} from "./types.js";
import {enqueueDailyCleanupSuite, processJobById} from "./runner.js";
import {enqueueCloudTask} from "./tasksEnqueue.js";
import {retryStaleProcessingPhotos} from "../moderation/photoModerationService.js";
import {getStorage} from "firebase-admin/storage";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const REGION = "europe-west1";

export const processAutomationTask = onTaskDispatched(
  {
    region: REGION,
    retryConfig: {
      maxAttempts: 5,
      minBackoffSeconds: 10,
      maxBackoffSeconds: 600,
      maxDoublings: 5,
    },
    rateLimits: {
      maxConcurrentDispatches: 5,
      maxDispatchesPerSecond: 2,
    },
  },
  async (req) => {
    const jobId = String(req.data?.jobId ?? "");
    if (!jobId) {
      return;
    }
    await processJobById(jobId);
  },
);

/** Report created → admin review queue (never auto-ban). */
export const onReportCreated = onDocumentCreated(
  {document: "reports/{reportId}", region: REGION},
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }
    const data = snap.data();
    const reportId = event.params.reportId;
    const reason = String(data.reason ?? "other");
    const critical = reason === "underage" || reason === "scam" || reason === "harassment";
    await db.doc(`adminReviewQueue/${reportId}`).set(
      {
        type: "report",
        reportId,
        reporterId: data.reporterId ?? null,
        reportedUserId: data.reportedUserId ?? null,
        reason,
        status: ReviewQueueStatus.open,
        priority: critical ? "high" : "normal",
        requiresHumanReview: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    await enqueueJob({
      kind: JobKind.reportEnqueueReview,
      idempotencyKey: `report_review_${reportId}`,
      payload: {reportId, reason},
      createdBy: "system",
      requiresHumanReview: true,
    });
  },
);

/** Daily retention + cleanup enqueue (replaces inline-only retention). */
export const automationDailySchedule = onSchedule(
  {schedule: "every 24 hours", region: REGION},
  async () => {
    const ids = await enqueueDailyCleanupSuite("scheduler");
    for (const jobId of ids) {
      await enqueueCloudTask(jobId);
    }
    const retriedPhotos = await retryStaleProcessingPhotos(db, getStorage().bucket());
    logger.info("automationDailySchedule", {enqueued: ids.length, retriedPhotos});
  },
);

/** Drain queued/retrying jobs (Cloud Tasks fallback + retries). */
export const automationJobDrain = onSchedule(
  {schedule: "every 15 minutes", region: REGION},
  async () => {
    const [queued, retrying] = await Promise.all([
      db.collection("automationJobs").where("status", "==", "queued").limit(20).get(),
      db.collection("automationJobs").where("status", "==", "retrying").limit(10).get(),
    ]);
    const docs = [...queued.docs, ...retrying.docs];
    let processed = 0;
    for (const doc of docs) {
      if (doc.data().requiresHumanReview === true && doc.data().status === "queued") {
        continue;
      }
      await processJobById(doc.id);
      processed += 1;
    }
    logger.info("automationJobDrain", {
      processed,
      failedRemaining: (
        await db.collection("automationJobs").where("status", "==", "failed").limit(20).get()
      ).size,
    });
  },
);

