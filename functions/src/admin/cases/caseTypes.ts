import {AdminError} from "../errors.js";

/**
 * Moderation case model.
 *
 * A case is the investigation / workflow around one subject. It does not own
 * the evidence: it points at the existing source records (reports, the photo
 * ledger, humor queue entries, support tickets, automation jobs, appeals)
 * through `sourceRefs`, and those stay exactly where they are. A case is also
 * not a sanction — the decisions taken while working it are separate
 * moderationActions linked through `actionIds`.
 */
export const CASE_COLLECTION = "moderationCases";
export const CASE_KEY_COLLECTION = "moderationCaseKeys";

export const CASE_TYPES = [
  "USER_REPORT",
  "PHOTO_REVIEW",
  "HUMOR_REVIEW",
  "VERIFICATION_REVIEW",
  "SUPPORT_ESCALATION",
  "AUTOMATION_REVIEW",
  "APPEAL",
] as const;
export type CaseType = (typeof CASE_TYPES)[number];

export const CASE_STATUSES = [
  "open",
  "assigned",
  "in_review",
  "waiting",
  "resolved",
  "dismissed",
] as const;
export type CaseStatus = (typeof CASE_STATUSES)[number];

export const ACTIVE_CASE_STATUSES: readonly CaseStatus[] = ["open", "assigned", "in_review", "waiting"];
export const TERMINAL_CASE_STATUSES: readonly CaseStatus[] = ["resolved", "dismissed"];

export function isTerminalCaseStatus(status: CaseStatus): boolean {
  return TERMINAL_CASE_STATUSES.includes(status);
}

export const PRIORITIES = ["low", "normal", "medium", "high", "critical"] as const;
export type Priority = (typeof PRIORITIES)[number];

/** Numeric rank stored next to the label so queues can sort on it. */
export const PRIORITY_RANK: Readonly<Record<Priority, number>> = {
  low: 0,
  normal: 1,
  medium: 2,
  high: 3,
  critical: 4,
};

export function maxPriority(a: Priority, b: Priority): Priority {
  return PRIORITY_RANK[a] >= PRIORITY_RANK[b] ? a : b;
}

export function bumpPriority(priority: Priority, floor: Priority = "normal"): Priority {
  const next = PRIORITIES[Math.min(PRIORITY_RANK[priority] + 1, PRIORITIES.length - 1)];
  return maxPriority(next, floor);
}

export function parsePriority(raw: unknown): Priority {
  return typeof raw === "string" && (PRIORITIES as readonly string[]).includes(raw)
    ? (raw as Priority)
    : "normal";
}

/**
 * The finite state machine. A transition not listed here is refused with
 * `invalid_state_transition`, whatever the caller asked for.
 */
export const CASE_TRANSITIONS: Readonly<Record<CaseStatus, readonly CaseStatus[]>> = {
  open: ["assigned", "in_review", "waiting", "resolved", "dismissed"],
  assigned: ["open", "in_review", "waiting", "resolved", "dismissed"],
  in_review: ["assigned", "open", "waiting", "resolved", "dismissed"],
  waiting: ["assigned", "open", "in_review", "resolved", "dismissed"],
  resolved: [],
  dismissed: [],
};

export function canTransition(from: CaseStatus, to: CaseStatus): boolean {
  return CASE_TRANSITIONS[from].includes(to);
}

export function assertTransition(from: CaseStatus, to: CaseStatus): void {
  if (!canTransition(from, to)) {
    throw new AdminError("invalid_state_transition", "invalid_state_transition", {from, to});
  }
}

export function parseCaseStatus(raw: unknown): CaseStatus {
  return typeof raw === "string" && (CASE_STATUSES as readonly string[]).includes(raw)
    ? (raw as CaseStatus)
    : "open";
}

export const RESOLUTION_CODES = [
  "action_taken",
  "no_violation",
  "insufficient_evidence",
  "duplicate",
  "subject_deleted",
  "resolved_elsewhere",
  "other",
] as const;
export type ResolutionCode = (typeof RESOLUTION_CODES)[number];

/** A case may name at most this many source records inline. */
export const MAX_SOURCE_REFS = 100;

export interface CaseDoc {
  caseId: string;
  type: CaseType;
  subjectUserId: string | null;
  subjectRef: string | null;
  sourceRefs: string[];
  sourceCount: number;
  reasonCodes: string[];
  reporterIds: string[];
  reporterCount: number;
  priority: Priority;
  priorityRank: number;
  status: CaseStatus;
  assignedTo: string | null;
  escalated: boolean;
  escalationLevel: number;
  correlationKey: string;
  actionIds: string[];
  summary: string | null;
  createdBy: string;
  resolvedBy: string | null;
  resolution: {outcome: "resolved" | "dismissed"; code: ResolutionCode} | null;
}

export function parseCaseDoc(caseId: string, data: Record<string, unknown> | undefined): CaseDoc | null {
  if (!data) {
    return null;
  }
  const type = (CASE_TYPES as readonly string[]).includes(String(data.type))
    ? (data.type as CaseType)
    : "USER_REPORT";
  const strings = (value: unknown) =>
    Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
  const priority = parsePriority(data.priority);
  const resolution = data.resolution && typeof data.resolution === "object"
    ? (data.resolution as CaseDoc["resolution"])
    : null;
  return {
    caseId,
    type,
    subjectUserId: typeof data.subjectUserId === "string" ? data.subjectUserId : null,
    subjectRef: typeof data.subjectRef === "string" ? data.subjectRef : null,
    sourceRefs: strings(data.sourceRefs),
    sourceCount: typeof data.sourceCount === "number" ? data.sourceCount : strings(data.sourceRefs).length,
    reasonCodes: strings(data.reasonCodes),
    reporterIds: strings(data.reporterIds),
    reporterCount: typeof data.reporterCount === "number" ? data.reporterCount : 0,
    priority,
    priorityRank: PRIORITY_RANK[priority],
    status: parseCaseStatus(data.status),
    assignedTo: typeof data.assignedTo === "string" ? data.assignedTo : null,
    escalated: data.escalated === true,
    escalationLevel: typeof data.escalationLevel === "number" ? data.escalationLevel : 0,
    correlationKey: typeof data.correlationKey === "string" ? data.correlationKey : "",
    actionIds: strings(data.actionIds),
    summary: typeof data.summary === "string" ? data.summary : null,
    createdBy: typeof data.createdBy === "string" ? data.createdBy : "system",
    resolvedBy: typeof data.resolvedBy === "string" ? data.resolvedBy : null,
    resolution,
  };
}
