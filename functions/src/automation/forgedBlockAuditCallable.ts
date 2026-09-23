import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {enqueueJob, requireAdmin} from "./jobs.js";
import {processJobById} from "./runner.js";
import {JobKind} from "./types.js";
import {DEFAULT_MAX_PAGES, DEFAULT_PAGE_SIZE} from "./forgedBlockAudit.js";
import {safeLogMeta} from "../security/logHygiene.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {enforceAppCheck, region: "europe-west1" as const};

/**
 * Admin-only trigger for the read-only legacy block audit (B-01 follow-up).
 *
 * Strictly a dry run: it scans `blocks`, classifies malformed documents and
 * files them in `adminReviewQueue`. It never writes to `blocks`. There is no
 * `delete` or `repair` parameter to pass, by design — a cleanup step would be
 * separate code requiring its own authorisation, because an ID heuristic is
 * not sufficient grounds to remove a safety record automatically.
 *
 * Gated by requireAdmin(), which reads the Auth custom claim only — never a
 * client-writable Firestore field — so an ordinary user cannot invoke it.
 */
export const runForgedBlockAudit = onCall(callableOptions, async (request) => {
  const uid = requireAdmin(request);

  const data = (request.data ?? {}) as Record<string, unknown>;
  const pageSize =
    typeof data.pageSize === "number" ? Math.max(1, Math.min(1000, data.pageSize)) : DEFAULT_PAGE_SIZE;
  const maxPages =
    typeof data.maxPages === "number" ? Math.max(1, data.maxPages) : DEFAULT_MAX_PAGES;
  const startAfterId = typeof data.startAfterId === "string" ? data.startAfterId : null;
  // Callers pass a run label so a deliberate re-scan gets its own job while an
  // accidental double-click collapses onto the existing one.
  const runId = typeof data.runId === "string" && data.runId.trim() ? data.runId.trim() : "default";
  if (runId.length > 100) {
    throw new HttpsError("invalid-argument", "runId-too-long");
  }

  const idempotencyKey = `${JobKind.forgedBlockAudit}__${runId}${startAfterId ? `__${startAfterId}` : ""}`;

  const {jobId, created, status} = await enqueueJob({
    kind: JobKind.forgedBlockAudit,
    idempotencyKey,
    payload: {pageSize, maxPages, startAfterId, jobId: idempotencyKey},
    createdBy: uid,
    maxAttempts: 1,
    db,
  });

  if (!created) {
    // Idempotent: the same run label does not start a second scan.
    logger.info("forged block audit already enqueued", safeLogMeta({jobId, status}));
    return {ok: true, jobId, created: false, status, dryRun: true};
  }

  const outcome = await processJobById(jobId, db);
  const jobSnap = await db.doc(`automationJobs/${jobId}`).get();

  return {
    ok: true,
    jobId,
    created: true,
    dryRun: true,
    outcome,
    result: jobSnap.data()?.result ?? null,
    status: jobSnap.data()?.status ?? status,
  };
});
