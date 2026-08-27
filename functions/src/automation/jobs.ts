import type {AutomationJob} from "./types.js";

export async function enqueueJob(
  job: AutomationJob,
): Promise<{jobId: string}> {
  return {jobId: job.idempotencyKey};
}
