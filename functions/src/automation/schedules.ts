import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {logger} from "firebase-functions";
import {JobStatus} from "./types.js";
import {processJobById} from "./runner.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const REGION = "europe-west1";

/**
 * Cloud Tasks target for `enqueueCloudTask`. Must stay named
 * `processAutomationTask` — the queue path in `tasksEnqueue.ts` is built from
 * this function name.
 */
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
    await processJobById(jobId, db);
  },
);

/**
 * Fallback drain for jobs whose Cloud Task never dispatched, plus scheduled
 * retries. Jobs flagged `requiresHumanReview` are left for an admin.
 */
export const automationJobDrain = onSchedule(
  {schedule: "every 15 minutes", region: REGION},
  async () => {
    const [queued, retrying] = await Promise.all([
      db
        .collection("automationJobs")
        .where("status", "==", JobStatus.queued)
        .limit(20)
        .get(),
      db
        .collection("automationJobs")
        .where("status", "==", JobStatus.retrying)
        .limit(10)
        .get(),
    ]);

    let processed = 0;
    for (const doc of [...queued.docs, ...retrying.docs]) {
      if (doc.data().requiresHumanReview === true) {
        continue;
      }
      await processJobById(doc.id, db);
      processed += 1;
    }

    logger.info("automationJobDrain", {
      scanned: queued.size + retrying.size,
      processed,
    });
  },
);
