import {FieldValue} from "firebase-admin/firestore";

/**
 * Moderation actions: `moderationActions/{actionId}`.
 *
 * An action is a decision that happened — a warning issued, an account
 * suspended, a photo rejected. It is never edited to mean something else and
 * never deleted by the admin platform: undoing a decision is a new action
 * (RESTORE_ACCOUNT, APPEAL_ACCEPTED) that points back at the old one, so the
 * history of what was decided, by whom and why is always complete.
 *
 * Contrast with a case (cases/caseTypes.ts), which is the investigation.
 */
export const ACTION_COLLECTION = "moderationActions";

export const ACTION_TYPES = [
  "WARNING",
  "PHOTO_APPROVED",
  "PHOTO_REJECTED",
  "PHOTO_REMOVED",
  "REQUIRE_REVERIFICATION",
  "TEMPORARY_SUSPENSION",
  "PERMANENT_BAN",
  "RESTORE_ACCOUNT",
  "SUSPENSION_EXPIRED",
  "SUPPORT_ESCALATION",
  "APPEAL_ACCEPTED",
  "APPEAL_REJECTED",
] as const;
export type ActionType = (typeof ACTION_TYPES)[number];

/** Action types a member may appeal against. */
export const APPEALABLE_ACTION_TYPES: readonly ActionType[] = [
  "WARNING",
  "TEMPORARY_SUSPENSION",
  "PERMANENT_BAN",
  "PHOTO_REJECTED",
  "PHOTO_REMOVED",
  "REQUIRE_REVERIFICATION",
];

/** Why a sanction was applied. Stable codes; the admin web localises them. */
export const REASON_CODES = [
  "HARASSMENT",
  "HATE_SPEECH",
  "SCAM_FRAUD",
  "SPAM",
  "FAKE_PROFILE",
  "IMPERSONATION",
  "UNDERAGE",
  "INAPPROPRIATE_CONTENT",
  "NUDITY_SEXUAL_CONTENT",
  "VIOLENCE_THREATS",
  "SELF_HARM_RISK",
  "BAN_EVASION",
  "PAYMENT_ABUSE",
  "TERMS_VIOLATION",
  "OTHER",
] as const;
export type ReasonCode = (typeof REASON_CODES)[number];

/** Why a restriction was lifted. */
export const RESTORE_REASON_CODES = [
  "APPEAL_ACCEPTED",
  "ERROR_CORRECTION",
  "SUSPENSION_REVIEWED",
  "NEW_EVIDENCE",
  "OTHER",
] as const;
export type RestoreReasonCode = (typeof RESTORE_REASON_CODES)[number];

/** Why a photo was rejected. Shown to the member in their own words. */
export const PHOTO_REJECT_REASONS = [
  "NUDITY_SEXUAL_CONTENT",
  "VIOLENCE_GORE",
  "HATE_SYMBOLS",
  "NOT_A_PERSON",
  "IMPERSONATION",
  "MINOR_IN_PHOTO",
  "LOW_QUALITY",
  "CONTACT_INFO",
  "OTHER",
] as const;
export type PhotoRejectReason = (typeof PHOTO_REJECT_REASONS)[number];

export interface ActionRecordInput {
  actionId: string;
  type: ActionType;
  targetUserId: string | null;
  caseId: string | null;
  reasonCode: string;
  internalNote: string | null;
  /** Shown to the affected member (warning text, appeal outcome). */
  userMessage?: string | null;
  actorAdminId: string;
  actorRole: string;
  requestId: string | null;
  idempotencyKey: string | null;
  effectiveAtMs: number;
  expiresAtMs?: number | null;
  previousState?: Record<string, unknown>;
  newState?: Record<string, unknown>;
  relatedActionId?: string | null;
  subject?: Record<string, unknown>;
}

export function buildActionRecord(input: ActionRecordInput): Record<string, unknown> {
  return {
    actionId: input.actionId,
    type: input.type,
    targetUserId: input.targetUserId,
    caseId: input.caseId,
    reasonCode: input.reasonCode,
    internalNote: input.internalNote,
    userMessage: input.userMessage ?? null,
    actorAdminId: input.actorAdminId,
    actorRole: input.actorRole,
    requestId: input.requestId,
    idempotencyKey: input.idempotencyKey,
    effectiveAt: new Date(input.effectiveAtMs),
    expiresAt: input.expiresAtMs ? new Date(input.expiresAtMs) : null,
    previousState: input.previousState ?? {},
    newState: input.newState ?? {},
    relatedActionId: input.relatedActionId ?? null,
    subject: input.subject ?? {},
    // Set when a later action (restore, accepted appeal) undoes this one.
    overturnedByActionId: null,
    appealId: null,
    createdAt: FieldValue.serverTimestamp(),
  };
}
