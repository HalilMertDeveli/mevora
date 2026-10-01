import {PRIORITY_RANK, type Priority} from "../cases/caseTypes.js";

/**
 * v1 report priority policy. Its keys are the production reason whitelist
 * (REPORT_REASONS below, which reportUser in social.ts validates against).
 * Computed on the server when the report is written; a client never supplies
 * a priority.
 *
 *   child_safety           critical  — sexual content or behaviour involving a
 *                                      minor (CSAE); the in-app child-safety
 *                                      report Google Play requires of dating apps
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
  child_safety: "critical",
  underage: "critical",
  harassment: "high",
  scam: "high",
  inappropriate_content: "high",
  fake_profile: "medium",
  spam: "normal",
  other: "normal",
};

/**
 * The reasons reportUser accepts. Derived from the priority table rather than
 * listed a second time, so a reason can never be accepted without an explicit
 * priority and silently take the `normal` of an unknown one.
 */
export const REPORT_REASONS: ReadonlySet<string> = new Set(Object.keys(REPORT_PRIORITY));

export function reportPriority(reason: unknown): {priority: Priority; priorityRank: number} {
  const priority = REPORT_PRIORITY[String(reason ?? "")] ?? "normal";
  return {priority, priorityRank: PRIORITY_RANK[priority]};
}

/** Correlation key: same subject + same reason → same open case. */
export function reportCorrelationKey(reportedUserId: string, reason: string): string {
  return `user_report:${reportedUserId}:${reason}`;
}
