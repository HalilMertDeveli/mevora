import {REASON_CODES, RESTORE_REASON_CODES, PHOTO_REJECT_REASONS} from "./actions/actionTypes.js";
import {AUDIT_ACTIONS} from "./audit/auditTypes.js";
import {ADMIN_ROLES} from "./auth/roles.js";
import {APPEAL_STATUSES, assignAppeal, getAppeal, listAppeals, openAppealForUser, resolveAppeal} from "./appeals/appealService.js";
import {listManualReviewJobs, resolveReviewItem, reviewAutomationJob} from "./automation/manualReviewQueue.js";
import {getCase, listCases} from "./cases/caseQueries.js";
import {addCaseNote, assignCase, escalateCase, openOrAttachCase, resolveCase, setCaseWorkingStatus} from "./cases/caseService.js";
import {CASE_STATUSES, CASE_TYPES, RESOLUTION_CODES} from "./cases/caseTypes.js";
import type {AdminCommandSpec} from "./command.js";
import {getDashboard, listAuditEvents} from "./dashboard.js";
import {HUMOR_QUEUE_STATUSES, getHumorReports, listHumorReviews, reviewHumorContent} from "./humor/humorReview.js";
import {PHOTO_QUEUE_FILTERS, getPhotoPreview, listPhotoReviews, reviewPhoto} from "./photos/photoReview.js";
import {REPORT_QUEUE_STATUSES, backfillReportPriority, listReports, openCaseForReport, resolveUserReport} from "./reports/reportQueue.js";
import {getMyStaffProfile, listStaff, recordAdminLogin, setStaffStatus, updateStaffRole} from "./staff/staffService.js";
import {
  TICKET_PRIORITIES,
  addSupportNote,
  assignSupportTicket,
  escalateSupportTicket,
  getSupportAttachment,
  getSupportTicket,
  listSupportTickets,
  replySupportTicket,
  resolveSupportTicket,
  updateSupportTicket,
} from "./support/supportService.js";
import {applyAccountAction, MAX_SUSPENSION_HOURS, MIN_SUSPENSION_HOURS} from "./users/accountActions.js";
import {getUserOverview} from "./users/getUserOverview.js";
import {getUserSafetyTimeline} from "./users/getUserSafetyTimeline.js";
import {SEARCH_MODES, searchUsers} from "./users/searchUsers.js";
import {LOOKUP_COLLECTION, lookupDocFor} from "./users/userLookup.js";
import {VERIFICATION_QUEUE_FILTERS, escalateVerification, getVerification, listVerificationReviews, requireReverification} from "./verification/verificationReview.js";
import {recordAuditEvent} from "./audit/auditService.js";
import {AdminError} from "./errors.js";
import {
  bool,
  docId,
  idempotencyKey,
  integer,
  oneOf,
  optionalDocId,
  optionalOneOf,
  optionalText,
  optionalUid,
  pageLimit,
  text,
  uid,
} from "./validation.js";

/**
 * The complete admin command surface. Each entry: one name, one permission,
 * one parser, one handler. Reviewing this file is reviewing everything the
 * console can do.
 */

const NOTE_MAX = 4000;
const REASON_MAX = 500;

// --- Session / staff --------------------------------------------------------

export const adminGetMyStaffProfileSpec: AdminCommandSpec<Record<string, never>, unknown> = {
  name: "adminGetMyStaffProfile",
  permission: "dashboard.read",
  rateClass: "read",
  parse: () => ({}),
  handler: ({deps, actor}) => getMyStaffProfile(deps, actor),
};

export const adminRecordLoginSpec: AdminCommandSpec<Record<string, never>, unknown> = {
  name: "adminRecordLogin",
  permission: "dashboard.read",
  rateClass: "sensitive",
  parse: () => ({}),
  handler: ({deps, actor, requestId}) => recordAdminLogin(deps, actor, requestId),
};

export const adminGetDashboardSpec: AdminCommandSpec<Record<string, never>, unknown> = {
  name: "adminGetDashboard",
  permission: "dashboard.read",
  rateClass: "read",
  parse: () => ({}),
  handler: ({deps, actor}) => getDashboard(deps, actor),
};

export const adminListStaffSpec: AdminCommandSpec<Record<string, never>, unknown> = {
  name: "adminListStaff",
  permission: "admin.manage_staff",
  rateClass: "read",
  parse: () => ({}),
  handler: ({deps}) => listStaff(deps),
};

export const adminUpdateStaffRoleSpec: AdminCommandSpec<
  {targetUid: string | null; email: string | null; role: (typeof ADMIN_ROLES)[number]; displayName: string | null},
  unknown
> = {
  name: "adminUpdateStaffRole",
  permission: "admin.manage_roles",
  rateClass: "sensitive",
  parse: (raw) => {
    const targetUid = optionalUid(raw.targetUid, "targetUid");
    const email = optionalText(raw.email, "email", 254);
    if (!targetUid && !email) {
      throw new AdminError("invalid_argument", "target");
    }
    return {
      targetUid,
      email,
      role: oneOf(raw.role, ADMIN_ROLES, "role"),
      displayName: optionalText(raw.displayName, "displayName", 80),
    };
  },
  handler: ({deps, actor, requestId}, input) => updateStaffRole(deps, actor, input, requestId),
};

export const adminDisableStaffSpec: AdminCommandSpec<{targetUid: string; reason: string}, unknown> = {
  name: "adminDisableStaff",
  permission: "admin.manage_staff",
  rateClass: "sensitive",
  parse: (raw) => ({targetUid: uid(raw.targetUid, "targetUid"), reason: text(raw.reason, "reason", {max: REASON_MAX, required: true})}),
  handler: ({deps, actor, requestId}, input) => setStaffStatus(deps, actor, {...input, status: "disabled"}, requestId),
};

export const adminEnableStaffSpec: AdminCommandSpec<{targetUid: string; reason: string}, unknown> = {
  name: "adminEnableStaff",
  permission: "admin.manage_staff",
  rateClass: "sensitive",
  parse: (raw) => ({targetUid: uid(raw.targetUid, "targetUid"), reason: text(raw.reason, "reason", {max: REASON_MAX, required: true})}),
  handler: ({deps, actor, requestId}, input) => setStaffStatus(deps, actor, {...input, status: "active"}, requestId),
};

// --- Users ------------------------------------------------------------------

export const adminSearchUsersSpec: AdminCommandSpec<Parameters<typeof searchUsers>[2], unknown> = {
  name: "adminSearchUsers",
  permission: "user.read",
  rateClass: "search",
  parse: (raw) => ({
    query: typeof raw.query === "string" ? raw.query.slice(0, 128) : "",
    mode: optionalOneOf(raw.mode, SEARCH_MODES, "mode") ?? "auto",
    status: optionalOneOf(raw.status, ["suspended", "banned"] as const, "status"),
    cursor: raw.cursor,
    limit: pageLimit(raw.limit, 20, 25),
  }),
  handler: ({deps, actor}, input) => searchUsers(deps, actor, input),
};

export const adminGetUserOverviewSpec: AdminCommandSpec<{uid: string; includeSensitive: boolean; justification: string | null}, unknown> = {
  name: "adminGetUserOverview",
  permission: "user.read",
  rateClass: "read",
  parse: (raw) => ({
    uid: uid(raw.uid),
    includeSensitive: bool(raw.includeSensitive),
    justification: optionalText(raw.justification, "justification", 300),
  }),
  handler: ({deps, actor, requestId}, input) => getUserOverview(deps, actor, input, requestId),
};

export const adminGetUserSafetyTimelineSpec: AdminCommandSpec<{uid: string; beforeMs: number | null; limit: number}, unknown> = {
  name: "adminGetUserSafetyTimeline",
  permission: "user.read",
  rateClass: "read",
  parse: (raw) => ({
    uid: uid(raw.uid),
    beforeMs: raw.beforeMs === undefined || raw.beforeMs === null ? null : integer(raw.beforeMs, "beforeMs", {min: 0, max: 8.64e15}),
    limit: pageLimit(raw.limit, 25, 25),
  }),
  handler: ({deps}, input) => getUserSafetyTimeline(deps, input),
};

const accountCommon = (raw: Record<string, unknown>) => ({
  targetUid: uid(raw.uid),
  internalNote: optionalText(raw.internalNote, "internalNote", NOTE_MAX),
  caseId: optionalDocId(raw.caseId, "caseId"),
  idempotencyKey: idempotencyKey(raw.idempotencyKey),
});

export const adminWarnUserSpec: AdminCommandSpec<ReturnType<typeof accountCommon> & {reasonCode: string; userMessage: string | null}, unknown> = {
  name: "adminWarnUser",
  permission: "user.warn",
  rateClass: "mutation",
  parse: (raw) => ({
    ...accountCommon(raw),
    reasonCode: oneOf(raw.reasonCode, REASON_CODES, "reasonCode"),
    userMessage: optionalText(raw.userMessage, "userMessage", 1000),
  }),
  handler: ({deps, actor, requestId}, input) => applyAccountAction(deps, actor, {
    ...input,
    command: {kind: "warn", reasonCode: input.reasonCode, userMessage: input.userMessage},
  }, requestId),
};

export const adminSuspendUserSpec: AdminCommandSpec<ReturnType<typeof accountCommon> & {reasonCode: string; durationHours: number}, unknown> = {
  name: "adminSuspendUser",
  permission: "user.suspend",
  rateClass: "mutation",
  parse: (raw) => {
    const common = accountCommon(raw);
    if (!common.internalNote) {
      throw new AdminError("invalid_argument", "internalNote");
    }
    return {
      ...common,
      reasonCode: oneOf(raw.reasonCode, REASON_CODES, "reasonCode"),
      durationHours: integer(raw.durationHours, "durationHours", {min: MIN_SUSPENSION_HOURS, max: MAX_SUSPENSION_HOURS}),
    };
  },
  handler: ({deps, actor, requestId}, input) => applyAccountAction(deps, actor, {
    ...input,
    command: {kind: "suspend", reasonCode: input.reasonCode, durationHours: input.durationHours},
  }, requestId),
};

export const adminBanUserSpec: AdminCommandSpec<ReturnType<typeof accountCommon> & {reasonCode: string}, unknown> = {
  name: "adminBanUser",
  permission: "user.ban",
  rateClass: "mutation",
  parse: (raw) => {
    const common = accountCommon(raw);
    if (!common.internalNote) {
      throw new AdminError("invalid_argument", "internalNote");
    }
    return {...common, reasonCode: oneOf(raw.reasonCode, REASON_CODES, "reasonCode")};
  },
  handler: ({deps, actor, requestId}, input) => applyAccountAction(deps, actor, {
    ...input,
    command: {kind: "ban", reasonCode: input.reasonCode},
  }, requestId),
};

export const adminRestoreUserSpec: AdminCommandSpec<ReturnType<typeof accountCommon> & {reasonCode: string}, unknown> = {
  name: "adminRestoreUser",
  permission: "user.restore",
  rateClass: "mutation",
  parse: (raw) => {
    const common = accountCommon(raw);
    if (!common.internalNote) {
      throw new AdminError("invalid_argument", "internalNote");
    }
    return {...common, reasonCode: oneOf(raw.reasonCode, RESTORE_REASON_CODES, "reasonCode")};
  },
  handler: ({deps, actor, requestId}, input) => applyAccountAction(deps, actor, {
    ...input,
    command: {kind: "restore", reasonCode: input.reasonCode},
  }, requestId),
};

// --- Cases ------------------------------------------------------------------

export const adminListCasesSpec: AdminCommandSpec<Parameters<typeof listCases>[2], unknown> = {
  name: "adminListCases",
  permission: "case.read",
  rateClass: "read",
  parse: (raw) => ({
    status: optionalOneOf(raw.status, ["active", ...CASE_STATUSES] as const, "status") ?? "active",
    type: optionalOneOf(raw.type, CASE_TYPES, "type"),
    assigned: optionalOneOf(raw.assigned, ["me", "any"] as const, "assigned") ?? "any",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps, actor}, input) => listCases(deps, actor, input),
};

export const adminGetCaseSpec: AdminCommandSpec<{caseId: string}, unknown> = {
  name: "adminGetCase",
  permission: "case.read",
  rateClass: "read",
  parse: (raw) => ({caseId: docId(raw.caseId, "caseId")}),
  handler: ({deps}, input) => getCase(deps, input.caseId),
};

export const adminAssignCaseSpec: AdminCommandSpec<{caseId: string; assigneeUid: string | null; unassign: boolean}, unknown> = {
  name: "adminAssignCase",
  permission: "case.assign",
  rateClass: "mutation",
  parse: (raw) => ({
    caseId: docId(raw.caseId, "caseId"),
    assigneeUid: optionalUid(raw.assigneeUid, "assigneeUid"),
    unassign: bool(raw.unassign),
  }),
  handler: ({deps, actor, requestId}, input) => assignCase(deps.db, actor, input, {requestId, nowMs: deps.now()}),
};

export const adminSetCaseStatusSpec: AdminCommandSpec<{caseId: string; status: "in_review" | "waiting" | "open"}, unknown> = {
  name: "adminSetCaseStatus",
  permission: "case.assign",
  rateClass: "mutation",
  parse: (raw) => ({caseId: docId(raw.caseId, "caseId"), status: oneOf(raw.status, ["in_review", "waiting", "open"] as const, "status")}),
  handler: ({deps, actor, requestId}, input) => setCaseWorkingStatus(deps.db, actor, input, {requestId, nowMs: deps.now()}),
};

export const adminResolveCaseSpec: AdminCommandSpec<Parameters<typeof resolveCase>[2], unknown> = {
  name: "adminResolveCase",
  permission: "case.resolve",
  rateClass: "mutation",
  parse: (raw) => ({
    caseId: docId(raw.caseId, "caseId"),
    outcome: oneOf(raw.outcome, ["resolved", "dismissed"] as const, "outcome"),
    code: oneOf(raw.code, RESOLUTION_CODES, "code"),
    note: optionalText(raw.note, "note", NOTE_MAX),
  }),
  handler: ({deps, actor, requestId}, input) => resolveCase(deps.db, actor, input, {requestId, nowMs: deps.now()}),
};

export const adminEscalateCaseSpec: AdminCommandSpec<{caseId: string; reason: string; note: string | null}, unknown> = {
  name: "adminEscalateCase",
  permission: "case.escalate",
  rateClass: "mutation",
  parse: (raw) => ({
    caseId: docId(raw.caseId, "caseId"),
    reason: text(raw.reason, "reason", {max: REASON_MAX, required: true}),
    note: optionalText(raw.note, "note", NOTE_MAX),
  }),
  handler: ({deps, actor, requestId}, input) => escalateCase(deps.db, actor, input, {requestId, nowMs: deps.now()}),
};

export const adminAddCaseNoteSpec: AdminCommandSpec<{caseId: string; text: string}, unknown> = {
  name: "adminAddCaseNote",
  permission: "case.note",
  rateClass: "mutation",
  parse: (raw) => ({caseId: docId(raw.caseId, "caseId"), text: text(raw.text, "text", {max: NOTE_MAX, required: true})}),
  handler: ({deps, actor, requestId}, input) => addCaseNote(deps.db, actor, input, {requestId, nowMs: deps.now()}),
};

// --- Reports ----------------------------------------------------------------

export const adminListReportsSpec: AdminCommandSpec<Parameters<typeof listReports>[1], unknown> = {
  name: "adminListReports",
  permission: "report.read",
  rateClass: "read",
  parse: (raw) => ({
    status: optionalOneOf(raw.status, REPORT_QUEUE_STATUSES, "status") ?? "open",
    reportedUserId: optionalUid(raw.reportedUserId, "reportedUserId"),
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps}, input) => listReports(deps, input),
};

export const adminResolveUserReportSpec: AdminCommandSpec<Parameters<typeof resolveUserReport>[2], unknown> = {
  name: "adminResolveUserReport",
  permission: "report.resolve",
  rateClass: "mutation",
  parse: (raw) => ({
    reportId: docId(raw.reportId, "reportId"),
    outcome: oneOf(raw.outcome, ["resolved", "dismissed"] as const, "outcome"),
    code: oneOf(raw.code, RESOLUTION_CODES, "code"),
    note: optionalText(raw.note, "note", NOTE_MAX),
  }),
  handler: ({deps, actor, requestId}, input) => resolveUserReport(deps, actor, input, requestId),
};

export const adminOpenReportCaseSpec: AdminCommandSpec<{reportId: string}, unknown> = {
  name: "adminOpenReportCase",
  permission: "report.assign",
  rateClass: "mutation",
  parse: (raw) => ({reportId: docId(raw.reportId, "reportId")}),
  handler: ({deps, actor, requestId}, input) => openCaseForReport(deps, actor, input, requestId),
};

// --- Photos -----------------------------------------------------------------

export const adminListPhotoReviewsSpec: AdminCommandSpec<Parameters<typeof listPhotoReviews>[1], unknown> = {
  name: "adminListPhotoReviews",
  permission: "photo.read",
  rateClass: "read",
  parse: (raw) => ({
    filter: optionalOneOf(raw.filter, PHOTO_QUEUE_FILTERS, "filter") ?? "manual_review",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit, 24, 48),
  }),
  handler: ({deps, actor}, input) => listPhotoReviews(deps, input, actor.uid),
};

export const adminGetPhotoPreviewSpec: AdminCommandSpec<{uid: string; imageId: string}, unknown> = {
  name: "adminGetPhotoPreview",
  permission: "photo.read",
  rateClass: "read",
  parse: (raw) => ({uid: uid(raw.uid), imageId: docId(raw.imageId, "imageId")}),
  handler: ({deps}, input) => getPhotoPreview(deps, input),
};

export const adminReviewPhotoSpec: AdminCommandSpec<Parameters<typeof reviewPhoto>[2], unknown> = {
  name: "adminReviewPhoto",
  permission: "photo.read",
  rateClass: "mutation",
  parse: (raw) => {
    const decision = oneOf(raw.decision, ["approve", "reject", "escalate"] as const, "decision");
    return {
      uid: uid(raw.uid),
      imageId: docId(raw.imageId, "imageId"),
      decision,
      reasonCode: decision === "reject"
        ? oneOf(raw.reasonCode, PHOTO_REJECT_REASONS, "reasonCode")
        : optionalText(raw.reasonCode, "reasonCode", 64),
      internalNote: optionalText(raw.internalNote, "internalNote", NOTE_MAX),
      caseId: optionalDocId(raw.caseId, "caseId"),
      idempotencyKey: idempotencyKey(raw.idempotencyKey),
    };
  },
  handler: async ({deps, actor, requestId}, input) => {
    // One command, three decisions, three permissions — checked per decision.
    const needed = input.decision === "approve" ? "photo.approve" : input.decision === "reject" ? "photo.reject" : "photo.escalate";
    if (!actor.permissions.has(needed)) {
      throw new AdminError("permission_denied", "permission_denied", {permission: needed});
    }
    return reviewPhoto(deps, actor, input, requestId);
  },
};

// --- Humor ------------------------------------------------------------------

export const adminListHumorReviewsSpec: AdminCommandSpec<Parameters<typeof listHumorReviews>[1], unknown> = {
  name: "adminListHumorReviews",
  permission: "humor.read",
  rateClass: "read",
  parse: (raw) => ({
    status: optionalOneOf(raw.status, HUMOR_QUEUE_STATUSES, "status") ?? "needs_review",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps}, input) => listHumorReviews(deps, input),
};

export const adminGetHumorReportsSpec: AdminCommandSpec<{contentId: string}, unknown> = {
  name: "adminGetHumorReports",
  permission: "humor.read",
  rateClass: "read",
  parse: (raw) => ({contentId: docId(raw.contentId, "contentId")}),
  handler: ({deps}, input) => getHumorReports(deps, input.contentId),
};

export const adminReviewHumorContentSpec: AdminCommandSpec<Parameters<typeof reviewHumorContent>[2], unknown> = {
  name: "adminReviewHumorContent",
  permission: "humor.moderate",
  rateClass: "mutation",
  parse: (raw) => ({
    contentId: docId(raw.contentId, "contentId"),
    decision: oneOf(raw.decision, ["approve", "reject", "escalate"] as const, "decision"),
    note: optionalText(raw.note, "note", NOTE_MAX),
  }),
  handler: ({deps, actor, requestId}, input) => reviewHumorContent(deps, actor, input, requestId),
};

// --- Verification -----------------------------------------------------------

export const adminGetVerificationSpec: AdminCommandSpec<{uid: string}, unknown> = {
  name: "adminGetVerification",
  permission: "verification.read",
  rateClass: "read",
  parse: (raw) => ({uid: uid(raw.uid)}),
  handler: ({deps}, input) => getVerification(deps, input.uid),
};

export const adminListVerificationReviewsSpec: AdminCommandSpec<Parameters<typeof listVerificationReviews>[1], unknown> = {
  name: "adminListVerificationReviews",
  permission: "verification.read",
  rateClass: "read",
  parse: (raw) => ({
    filter: optionalOneOf(raw.filter, VERIFICATION_QUEUE_FILTERS, "filter") ?? "in_review",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps}, input) => listVerificationReviews(deps, input),
};

export const adminRequireReverificationSpec: AdminCommandSpec<Parameters<typeof requireReverification>[2], unknown> = {
  name: "adminRequireReverification",
  permission: "verification.require_reverification",
  rateClass: "mutation",
  parse: (raw) => ({
    uid: uid(raw.uid),
    reasonCode: oneOf(raw.reasonCode, REASON_CODES, "reasonCode"),
    internalNote: text(raw.internalNote, "internalNote", {max: NOTE_MAX, required: true}),
    caseId: optionalDocId(raw.caseId, "caseId"),
    idempotencyKey: idempotencyKey(raw.idempotencyKey),
  }),
  handler: ({deps, actor, requestId}, input) => requireReverification(deps, actor, input, requestId),
};

export const adminEscalateVerificationSpec: AdminCommandSpec<{uid: string; reason: string; note: string | null}, unknown> = {
  name: "adminEscalateVerification",
  permission: "verification.escalate",
  rateClass: "mutation",
  parse: (raw) => ({
    uid: uid(raw.uid),
    reason: text(raw.reason, "reason", {max: REASON_MAX, required: true}),
    note: optionalText(raw.note, "note", NOTE_MAX),
  }),
  handler: ({deps, actor, requestId}, input) => escalateVerification(deps, actor, input, requestId),
};

// --- Support ----------------------------------------------------------------

export const adminListSupportTicketsSpec: AdminCommandSpec<Parameters<typeof listSupportTickets>[2], unknown> = {
  name: "adminListSupportTickets",
  permission: "support.read",
  rateClass: "read",
  parse: (raw) => ({
    status: optionalOneOf(raw.status, ["active", "all", "open", "in_progress", "resolved", "closed"] as const, "status") ?? "active",
    assigned: optionalOneOf(raw.assigned, ["me", "any"] as const, "assigned") ?? "any",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps, actor}, input) => listSupportTickets(deps, actor, input),
};

export const adminGetSupportTicketSpec: AdminCommandSpec<{ticketId: string}, unknown> = {
  name: "adminGetSupportTicket",
  permission: "support.read",
  rateClass: "read",
  parse: (raw) => ({ticketId: docId(raw.ticketId, "ticketId")}),
  handler: ({deps}, input) => getSupportTicket(deps, input.ticketId),
};

export const adminGetSupportAttachmentSpec: AdminCommandSpec<{ticketId: string; index: number}, unknown> = {
  name: "adminGetSupportAttachment",
  permission: "support.read",
  rateClass: "read",
  parse: (raw) => ({ticketId: docId(raw.ticketId, "ticketId"), index: integer(raw.index, "index", {min: 0, max: 2})}),
  handler: ({deps}, input) => getSupportAttachment(deps, input),
};

export const adminAssignSupportTicketSpec: AdminCommandSpec<{ticketId: string; assigneeUid: string | null}, unknown> = {
  name: "adminAssignSupportTicket",
  permission: "support.assign",
  rateClass: "mutation",
  parse: (raw) => ({ticketId: docId(raw.ticketId, "ticketId"), assigneeUid: optionalUid(raw.assigneeUid, "assigneeUid")}),
  handler: ({deps, actor, requestId}, input) => assignSupportTicket(deps, actor, input, requestId),
};

export const adminReplySupportTicketSpec: AdminCommandSpec<{ticketId: string; text: string; idempotencyKey: string}, unknown> = {
  name: "adminReplySupportTicket",
  permission: "support.reply",
  rateClass: "mutation",
  parse: (raw) => ({
    ticketId: docId(raw.ticketId, "ticketId"),
    text: text(raw.text, "text", {max: NOTE_MAX, required: true}),
    idempotencyKey: idempotencyKey(raw.idempotencyKey),
  }),
  handler: ({deps, actor, requestId}, input) => replySupportTicket(deps, actor, input, requestId),
};

export const adminAddSupportNoteSpec: AdminCommandSpec<{ticketId: string; text: string}, unknown> = {
  name: "adminAddSupportNote",
  permission: "support.read",
  rateClass: "mutation",
  parse: (raw) => ({ticketId: docId(raw.ticketId, "ticketId"), text: text(raw.text, "text", {max: NOTE_MAX, required: true})}),
  handler: ({deps, actor, requestId}, input) => addSupportNote(deps, actor, input, requestId),
};

export const adminUpdateSupportTicketSpec: AdminCommandSpec<Parameters<typeof updateSupportTicket>[2], unknown> = {
  name: "adminUpdateSupportTicket",
  permission: "support.assign",
  rateClass: "mutation",
  parse: (raw) => {
    const status = optionalOneOf(raw.status, ["in_progress", "open"] as const, "status");
    const priority = optionalOneOf(raw.priority, TICKET_PRIORITIES, "priority");
    if (!status && !priority) {
      throw new AdminError("invalid_argument", "nothing_to_update");
    }
    return {ticketId: docId(raw.ticketId, "ticketId"), status, priority};
  },
  handler: ({deps, actor, requestId}, input) => updateSupportTicket(deps, actor, input, requestId),
};

export const adminResolveSupportTicketSpec: AdminCommandSpec<Parameters<typeof resolveSupportTicket>[2], unknown> = {
  name: "adminResolveSupportTicket",
  permission: "support.resolve",
  rateClass: "mutation",
  parse: (raw) => ({
    ticketId: docId(raw.ticketId, "ticketId"),
    outcome: oneOf(raw.outcome, ["resolved", "closed"] as const, "outcome"),
    resolutionNote: optionalText(raw.resolutionNote, "resolutionNote", NOTE_MAX),
  }),
  handler: ({deps, actor, requestId}, input) => resolveSupportTicket(deps, actor, input, requestId),
};

export const adminEscalateSupportTicketSpec: AdminCommandSpec<Parameters<typeof escalateSupportTicket>[2], unknown> = {
  name: "adminEscalateSupportTicket",
  permission: "support.escalate",
  rateClass: "mutation",
  parse: (raw) => ({
    ticketId: docId(raw.ticketId, "ticketId"),
    reason: text(raw.reason, "reason", {max: REASON_MAX, required: true}),
    priority: optionalOneOf(raw.priority, ["normal", "medium", "high", "critical"] as const, "priority") ?? "high",
    idempotencyKey: idempotencyKey(raw.idempotencyKey),
  }),
  handler: ({deps, actor, requestId}, input) => escalateSupportTicket(deps, actor, input, requestId),
};

// --- Automation -------------------------------------------------------------

export const adminListManualReviewJobsSpec: AdminCommandSpec<Parameters<typeof listManualReviewJobs>[2], unknown> = {
  name: "adminListManualReviewJobs",
  permission: "automation.read",
  rateClass: "read",
  parse: (raw) => ({
    status: optionalOneOf(raw.status, ["manual_review", "failed"] as const, "status") ?? "manual_review",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps, actor}, input) => listManualReviewJobs(deps, actor, input),
};

export const adminReviewAutomationJobSpec: AdminCommandSpec<Parameters<typeof reviewAutomationJob>[2], unknown> = {
  name: "adminReviewAutomationJob",
  permission: "automation.read",
  rateClass: "mutation",
  parse: (raw) => ({
    jobId: docId(raw.jobId, "jobId"),
    action: oneOf(raw.action, ["retry", "resolve", "dismiss", "escalate"] as const, "action"),
    note: text(raw.note, "note", {max: NOTE_MAX, required: true}),
  }),
  // Per-kind policy (allowedJobActions) enforces automation.review /
  // automation.resolve_sensitive inside the handler.
  handler: ({deps, actor, requestId}, input) => reviewAutomationJob(deps, actor, input, requestId),
};

export const adminResolveReviewItemSpec: AdminCommandSpec<Parameters<typeof resolveReviewItem>[2], unknown> = {
  name: "adminResolveReviewItem",
  permission: "automation.review",
  rateClass: "mutation",
  parse: (raw) => ({
    itemId: docId(raw.itemId, "itemId"),
    outcome: oneOf(raw.outcome, ["resolved", "dismissed"] as const, "outcome"),
    note: text(raw.note, "note", {max: NOTE_MAX, required: true}),
  }),
  handler: ({deps, actor, requestId}, input) => resolveReviewItem(deps, actor, input, requestId),
};

// --- Appeals ----------------------------------------------------------------

export const adminListAppealsSpec: AdminCommandSpec<Parameters<typeof listAppeals>[1], unknown> = {
  name: "adminListAppeals",
  permission: "appeal.read",
  rateClass: "read",
  parse: (raw) => ({
    status: optionalOneOf(raw.status, APPEAL_STATUSES, "status") ?? "open",
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps}, input) => listAppeals(deps, input),
};

export const adminGetAppealSpec: AdminCommandSpec<{appealId: string}, unknown> = {
  name: "adminGetAppeal",
  permission: "appeal.read",
  rateClass: "read",
  parse: (raw) => ({appealId: docId(raw.appealId, "appealId")}),
  handler: ({deps}, input) => getAppeal(deps, input.appealId),
};

export const adminAssignAppealSpec: AdminCommandSpec<{appealId: string}, unknown> = {
  name: "adminAssignAppeal",
  permission: "appeal.assign",
  rateClass: "mutation",
  parse: (raw) => ({appealId: docId(raw.appealId, "appealId")}),
  handler: ({deps, actor, requestId}, input) => assignAppeal(deps, actor, input, requestId),
};

export const adminResolveAppealSpec: AdminCommandSpec<Parameters<typeof resolveAppeal>[2], unknown> = {
  name: "adminResolveAppeal",
  permission: "appeal.resolve",
  rateClass: "mutation",
  parse: (raw) => ({
    appealId: docId(raw.appealId, "appealId"),
    decision: oneOf(raw.decision, ["accept", "reject"] as const, "decision"),
    userMessage: text(raw.userMessage, "userMessage", {max: 1000, required: true}),
    internalNote: optionalText(raw.internalNote, "internalNote", NOTE_MAX),
    idempotencyKey: idempotencyKey(raw.idempotencyKey),
  }),
  handler: ({deps, actor, requestId}, input) => resolveAppeal(deps, actor, input, requestId),
};

export const adminOpenAppealSpec: AdminCommandSpec<Parameters<typeof openAppealForUser>[2], unknown> = {
  name: "adminOpenAppeal",
  permission: "appeal.create",
  rateClass: "mutation",
  parse: (raw) => ({
    userId: uid(raw.userId, "userId"),
    moderationActionId: docId(raw.moderationActionId, "moderationActionId"),
    reason: text(raw.reason, "reason", {max: 2000, min: 10}),
    ticketId: optionalDocId(raw.ticketId, "ticketId"),
  }),
  handler: ({deps, actor, requestId}, input) => openAppealForUser(deps, actor, input, requestId),
};

// --- Audit & maintenance ----------------------------------------------------

export const adminListAuditEventsSpec: AdminCommandSpec<Parameters<typeof listAuditEvents>[1], unknown> = {
  name: "adminListAuditEvents",
  permission: "audit.read",
  rateClass: "read",
  parse: (raw) => ({
    actorAdminId: optionalUid(raw.actorAdminId, "actorAdminId"),
    targetId: optionalText(raw.targetId, "targetId", 300),
    action: optionalOneOf(raw.action, AUDIT_ACTIONS, "action"),
    cursor: raw.cursor,
    limit: pageLimit(raw.limit),
  }),
  handler: ({deps}, input) => listAuditEvents(deps, input),
};

export const adminBackfillReportPrioritySpec: AdminCommandSpec<{cursor: string | null; pageSize: number}, unknown> = {
  name: "adminBackfillReportPriority",
  permission: "admin.maintenance",
  rateClass: "sensitive",
  parse: (raw) => ({cursor: optionalDocId(raw.cursor, "cursor"), pageSize: pageLimit(raw.pageSize, 300, 400)}),
  handler: async ({deps, actor, requestId}, input) => {
    const result = await backfillReportPriority(deps, input);
    await recordAuditEvent(deps.db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "MAINTENANCE_RUN",
      targetType: "system",
      targetId: "reports.priority",
      requestId,
      metadata: {scanned: result.scanned, updated: result.updated},
    }, deps.now());
    return result;
  },
};

export const adminRebuildUserLookupSpec: AdminCommandSpec<{cursor: string | null; pageSize: number}, unknown> = {
  name: "adminRebuildUserLookup",
  permission: "admin.maintenance",
  rateClass: "sensitive",
  parse: (raw) => ({cursor: raw.cursor ? uid(raw.cursor, "cursor") : null, pageSize: pageLimit(raw.pageSize, 300, 400)}),
  handler: async ({deps, actor, requestId}, input) => {
    let q = deps.db.collection("profiles").orderBy("__name__").limit(input.pageSize);
    if (input.cursor) {
      q = q.startAfter(input.cursor);
    }
    const snap = await q.get();
    const batch = deps.db.batch();
    let written = 0;
    for (const doc of snap.docs) {
      const next = lookupDocFor(doc.id, doc.data());
      if (next) {
        batch.set(deps.db.doc(`${LOOKUP_COLLECTION}/${doc.id}`), next, {merge: true});
        written += 1;
      }
    }
    if (written) {
      await batch.commit();
    }
    await recordAuditEvent(deps.db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "MAINTENANCE_RUN",
      targetType: "system",
      targetId: "adminUserLookup",
      requestId,
      metadata: {scanned: snap.size, written},
    }, deps.now());
    const last = snap.docs[snap.docs.length - 1];
    return {scanned: snap.size, written, nextCursor: snap.size === input.pageSize && last ? last.id : null};
  },
};

/** Staff opens a case by hand (e.g. from a user's page). */
export const adminOpenCaseSpec: AdminCommandSpec<{
  type: (typeof CASE_TYPES)[number];
  subjectUserId: string;
  reasonCode: string;
  priority: "normal" | "medium" | "high" | "critical";
  summary: string;
}, unknown> = {
  name: "adminOpenCase",
  permission: "case.assign",
  rateClass: "mutation",
  parse: (raw) => ({
    type: oneOf(raw.type, CASE_TYPES, "type"),
    subjectUserId: uid(raw.subjectUserId, "subjectUserId"),
    reasonCode: text(raw.reasonCode, "reasonCode", {max: 64, required: true}),
    priority: optionalOneOf(raw.priority, ["normal", "medium", "high", "critical"] as const, "priority") ?? "normal",
    summary: text(raw.summary, "summary", {max: 300, required: true}),
  }),
  handler: ({deps, actor, requestId}, input) => openOrAttachCase(deps.db, {
    type: input.type,
    correlationKey: `manual:${input.type}:${input.subjectUserId}:${input.reasonCode}`,
    subjectUserId: input.subjectUserId,
    sourceRef: `users/${input.subjectUserId}`,
    reasonCode: input.reasonCode,
    priority: input.priority,
    summary: input.summary,
    createdBy: actor.uid,
    createdByRole: actor.role,
    requestId,
  }, deps.now()),
};

