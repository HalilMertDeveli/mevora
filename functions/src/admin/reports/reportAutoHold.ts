import type {Firestore} from "firebase-admin/firestore";

import {REPORT_PRIORITY} from "./reportPriority.js";

/**
 * When a report takes the reported member's photos out of circulation on its
 * own, before a moderator has looked.
 *
 * Holding the photos sends them to manual review and, because a member with no
 * showable photo is not eligible, removes the member from everyone's Picks
 * until staff decide. That is the right reflex for a possible minor — and a
 * weapon in anyone's hands if a single report of any kind can do it: one
 * member could hide another by reporting them as spam.
 *
 * Owner decision, 2026-10-02:
 *
 *   - a `critical` reason (child_safety, underage) holds at once, on the
 *     first report;
 *   - every other reason holds only once AUTO_HOLD_DISTINCT_REPORTERS
 *     different members have an open report against the same member inside
 *     AUTO_HOLD_WINDOW_MS.
 *
 * Every report still reaches the moderation queue either way; this decides
 * only the automatic hold.
 */
export const AUTO_HOLD_DISTINCT_REPORTERS = 3;
export const AUTO_HOLD_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

/** Open reports read per decision; far above any honest count for one member. */
const OPEN_REPORT_SCAN_LIMIT = 200;

export type AutoHoldCause = "critical_reason" | "reporter_threshold";

export interface AutoHoldDecision {
  hold: boolean;
  cause: AutoHoldCause | null;
  /** Different members with an open report in the window, the new one included. */
  distinctReporters: number;
}

/** Whether a report with this reason holds the photos without waiting for others. */
export function reasonHoldsAtOnce(reason: string): boolean {
  return REPORT_PRIORITY[reason] === "critical";
}

function millisOf(value: unknown): number | null {
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  const maybe = value as {toMillis?: () => number; toDate?: () => Date} | null | undefined;
  if (typeof maybe?.toMillis === "function") {
    return maybe.toMillis();
  }
  if (typeof maybe?.toDate === "function") {
    return maybe.toDate().getTime();
  }
  return null;
}

/**
 * Different members among [reports] whose report is recent enough to count.
 * A report whose time cannot be read is counted: it was just written and its
 * server timestamp has not resolved yet.
 */
export function distinctRecentReporters(
  reports: ReadonlyArray<{reporterId?: unknown; createdAt?: unknown}>,
  nowMs: number,
): Set<string> {
  const reporters = new Set<string>();
  for (const report of reports) {
    const reporterId = String(report.reporterId ?? "");
    if (!reporterId) {
      continue;
    }
    const createdAtMs = millisOf(report.createdAt);
    if (createdAtMs !== null && nowMs - createdAtMs > AUTO_HOLD_WINDOW_MS) {
      continue;
    }
    reporters.add(reporterId);
  }
  return reporters;
}

/**
 * Decides the automatic hold for a report that has just been stored.
 *
 * Only open reports count, so once staff close the reports about a member the
 * count starts again. Two equality filters keep the query on the automatic
 * single-field indexes; the window is applied in memory.
 */
export async function decideAutoHold(
  db: Firestore,
  report: {reporterId: string; reportedUserId: string; reason: string},
  nowMs: number = Date.now(),
): Promise<AutoHoldDecision> {
  if (reasonHoldsAtOnce(report.reason)) {
    return {hold: true, cause: "critical_reason", distinctReporters: 1};
  }
  const open = await db
    .collection("reports")
    .where("reportedUserId", "==", report.reportedUserId)
    .where("status", "==", "open")
    .limit(OPEN_REPORT_SCAN_LIMIT)
    .get();
  const reporters = distinctRecentReporters(
    open.docs.map((doc) => doc.data()),
    nowMs,
  );
  reporters.add(report.reporterId);
  const hold = reporters.size >= AUTO_HOLD_DISTINCT_REPORTERS;
  return {hold, cause: hold ? "reporter_threshold" : null, distinctReporters: reporters.size};
}
