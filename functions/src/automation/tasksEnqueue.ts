import {getFunctions} from "firebase-admin/functions";
import {logger} from "firebase-functions";

const REGION = "europe-west1";

/** Enqueue Cloud Task for processAutomationTask. Falls back silently on emulator. */
export async function enqueueCloudTask(jobId: string): Promise<void> {
  try {
    const queue = getFunctions().taskQueue(
      `locations/${REGION}/functions/processAutomationTask`,
    );
    await queue.enqueue(
      {jobId},
      {
        id: jobId,
        dispatchDeadlineSeconds: 60 * 30,
      },
    );
  } catch (error) {
    logger.warn("Cloud Tasks enqueue failed; job remains queued for scheduler drain", {
      jobId,
      error: String(error),
    });
  }
}
