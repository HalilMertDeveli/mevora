import {PRIORITY_RANK, type Priority} from "../cases/caseTypes.js";

/**
 * v1 report priority policy, keyed on the production reason whitelist in
 * social.ts (REPORT_REASONS). Computed on the server when the report is
 * written; a client never supplies a priority.
 *
 *   underage               critical  — possible minor on an adult platform
 *   harassment             high
 *   scam                   high
 *   inappropriate_content  high
 *   fake_profile           medium
 *   spam                   normal
 *   other                  normal
 *
 * A reason outside the whitelist (legacy data) is treated as `normal` rather
 * than dropped, so it still reaches the queue.
 */
export const REPORT_PRIORITY: Readonly<Record<string, Priority>> = {
  underage: "critical",
  harassment: "high",
  scam: "high",
  inappropriate_content: "high",
  fake_profile: "medium",
  spam: "normal",
  other: "normal",
};

export function reportPriority(reason: unknown): {priority: Priority; priorityRank: number} {
  const priority = REPORT_PRIORITY[String(reason ?? "")] ?? "normal";
  return {priority, priorityRank: PRIORITY_RANK[priority]};
}

/** Correlation key: same subject + same reason → same open case. */
export function reportCorrelationKey(reportedUserId: string, reason: string): string {
  return `user_report:${reportedUserId}:${reason}`;
}
