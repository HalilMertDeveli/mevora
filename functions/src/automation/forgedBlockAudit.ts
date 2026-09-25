import {FieldValue, getFirestore, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {ReviewQueueStatus} from "./types.js";

/**
 * Read-only audit for legacy malformed `blocks/*` documents.
 *
 * B-01 bound the block document ID to the authenticated blocker, so a forged
 * pair can no longer be created. The rule governs new writes only: a document
 * written before the fix — for example blocks/{A}_{B} carrying blockerId C —
 * would still sever an unrelated pair, and neither victim can delete it
 * because delete requires blockerId == auth.uid.
 *
 * This job finds those records. It never repairs them. An ID heuristic is not
 * strong enough to justify deleting a safety record automatically: a false
 * positive would silently un-block someone who blocked a harasser. So the
 * lifecycle is deliberately
 *
 *     DRY-RUN AUDIT -> HUMAN REVIEW -> separately authorised cleanup
 *
 * and nothing in this file writes to `blocks`.
 */

export const BLOCKS_COLLECTION = "blocks";
export const REVIEW_COLLECTION = "adminReviewQueue";

/** Canonical block identity, shared with SafetyPolicy.blockId and ids.ts. */
export function canonicalBlockId(blockerId: string, blockedUserId: string): string {
  return `${blockerId}_${blockedUserId}`;
}

export const BlockAnomaly = {
  idMismatch: "id_mismatch",
  missingBlockerId: "missing_blocker_id",
  missingBlockedUserId: "missing_blocked_user_id",
  emptyBlockerId: "empty_blocker_id",
  emptyBlockedUserId: "empty_blocked_user_id",
  selfBlock: "self_block",
  invalidFieldType: "invalid_field_type",
} as const;

export type BlockAnomalyValue = (typeof BlockAnomaly)[keyof typeof BlockAnomaly];

export type BlockAuditFinding = {
  blockId: string;
  blockerId: string | null;
  blockedUserId: string | null;
  expectedId: string | null;
  anomalies: BlockAnomalyValue[];
};

/**
 * Classify one block document. Pure: no reads, no writes, no I/O — so the
 * rules that decide what counts as malformed are unit-testable on their own.
 *
 * Returns null for a well-formed document.
 */
export function classifyBlockDocument(
  blockId: string,
  data: Record<string, unknown> | undefined,
): BlockAuditFinding | null {
  const raw = data ?? {};
  const anomalies: BlockAnomalyValue[] = [];

  const blockerRaw = raw.blockerId;
  const blockedRaw = raw.blockedUserId;

  const blockerMissing = blockerRaw === undefined || blockerRaw === null;
  const blockedMissing = blockedRaw === undefined || blockedRaw === null;
  if (blockerMissing) {
    anomalies.push(BlockAnomaly.missingBlockerId);
  }
  if (blockedMissing) {
    anomalies.push(BlockAnomaly.missingBlockedUserId);
  }

  const blockerIsString = typeof blockerRaw === "string";
  const blockedIsString = typeof blockedRaw === "string";
  if ((!blockerMissing && !blockerIsString) || (!blockedMissing && !blockedIsString)) {
    anomalies.push(BlockAnomaly.invalidFieldType);
  }

  const blockerId = blockerIsString ? (blockerRaw as string) : null;
  const blockedUserId = blockedIsString ? (blockedRaw as string) : null;

  if (blockerIsString && blockerId === "") {
    anomalies.push(BlockAnomaly.emptyBlockerId);
  }
  if (blockedIsString && blockedUserId === "") {
    anomalies.push(BlockAnomaly.emptyBlockedUserId);
  }

  if (blockerId && blockedUserId && blockerId === blockedUserId) {
    anomalies.push(BlockAnomaly.selfBlock);
  }

  // The defect B-01 closed: the document ID must name the pair its fields
  // describe. Only checkable when both fields are usable strings.
  const expectedId =
    blockerId && blockedUserId ? canonicalBlockId(blockerId, blockedUserId) : null;
  if (expectedId && expectedId !== blockId) {
    anomalies.push(BlockAnomaly.idMismatch);
  }

  if (!anomalies.length) {
    return null;
  }
  return {
    blockId,
    blockerId,
    blockedUserId,
    expectedId,
    anomalies,
  };
}

export type ForgedBlockAuditOptions = {
  db?: Firestore;
  /** Documents per page. Keeps an unbounded collection off the heap. */
  pageSize?: number;
  /** Safety valve so one invocation cannot run forever. */
  maxPages?: number;
  /** Resume token: the last block document ID inspected by a prior run. */
  startAfterId?: string | null;
  /** Job document this scan belongs to; recorded on each finding. */
  jobId?: string;
};

export type ForgedBlockAuditResult = Record<string, unknown> & {
  scanned: number;
  flagged: number;
  pages: number;
  complete: boolean;
  /** Pass back as startAfterId to continue an incomplete scan. */
  nextCursor: string | null;
  anomalyCounts: Record<string, number>;
  dryRun: true;
  blockWrites: 0;
};

export const DEFAULT_PAGE_SIZE = 200;
export const DEFAULT_MAX_PAGES = 50;

/** Stable review-document id so re-running the audit updates, never duplicates. */
export function reviewDocId(blockId: string): string {
  return `forged_block__${blockId}`;
}

/**
 * Paginated, read-only scan of `blocks`. Findings go to `adminReviewQueue`
 * under a deterministic id, so repeated executions converge on the same set of
 * review rows rather than spamming new ones.
 *
 * Only audit metadata is recorded — the two uids already present on the block
 * document plus the anomaly. No profile, photo or privacy data is read.
 */
export async function auditForgedBlocks(
  options: ForgedBlockAuditOptions = {},
): Promise<ForgedBlockAuditResult> {
  const db = options.db ?? getFirestore();
  const pageSize = Math.max(1, Math.min(1000, options.pageSize ?? DEFAULT_PAGE_SIZE));
  const maxPages = Math.max(1, options.maxPages ?? DEFAULT_MAX_PAGES);
  const jobId = options.jobId ?? null;

  let cursor: string | null = options.startAfterId ?? null;
  let scanned = 0;
  let flagged = 0;
  let pages = 0;
  let complete = true;
  const anomalyCounts: Record<string, number> = {};

  for (;;) {
    if (pages >= maxPages) {
      // Stop and hand back a cursor rather than running unbounded.
      complete = false;
      break;
    }

    // Order by document id so the cursor is stable across runs.
    let query = db
      .collection(BLOCKS_COLLECTION)
      .orderBy("__name__")
      .limit(pageSize);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snap = await query.get();
    if (snap.empty) {
      break;
    }
    pages += 1;

    for (const doc of snap.docs) {
      scanned += 1;
      cursor = doc.id;
      const finding = classifyBlockDocument(doc.id, doc.data());
      if (!finding) {
        continue;
      }
      flagged += 1;
      for (const anomaly of finding.anomalies) {
        anomalyCounts[anomaly] = (anomalyCounts[anomaly] ?? 0) + 1;
      }
      await recordFinding(db, finding, jobId);
    }

    if (snap.size < pageSize) {
      break;
    }
  }

  const result: ForgedBlockAuditResult = {
    scanned,
    flagged,
    pages,
    complete,
    nextCursor: complete ? null : cursor,
    anomalyCounts,
    dryRun: true,
    blockWrites: 0,
  };

  logger.info(
    "forged block audit completed (dry run, no block documents modified)",
    safeLogMeta({jobId: jobId ?? "", scanned, flagged, complete}),
  );
  return result;
}

/**
 * Upsert one review row. Deterministic id + merge, so a second pass over the
 * same malformed document refreshes it instead of creating a duplicate.
 */
async function recordFinding(
  db: Firestore,
  finding: BlockAuditFinding,
  jobId: string | null,
): Promise<void> {
  await db
    .collection(REVIEW_COLLECTION)
    .doc(reviewDocId(finding.blockId))
    .set(
      {
        type: "forged_block_audit",
        status: ReviewQueueStatus.open,
        blockId: finding.blockId,
        blockerId: finding.blockerId,
        blockedUserId: finding.blockedUserId,
        expectedId: finding.expectedId,
        anomalies: finding.anomalies,
        jobId,
        // Explicit so a reviewer never mistakes this row for an applied change.
        remediation: "manual_review_required",
        auditedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
}
