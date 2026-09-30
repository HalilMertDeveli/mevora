import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import * as specs from "./commands.js";
import {ADMIN_REGION, defineAdminCommand} from "./command.js";
import type {AdminBucketPort} from "./deps.js";
import {expireSuspensions, runRetentionSweep} from "./retention.js";
import {syncLookupForProfile} from "./users/userLookup.js";

if (getApps().length === 0) {
  initializeApp();
}

/**
 * MEVORA Admin / Trust & Safety control plane.
 *
 * Every export below is either an explicit staff command (see commands.ts —
 * one permission each, authorised by authorizeAdminRequest), a consumer
 * callable for the member's side of moderation (App Check enforced), or
 * server-side upkeep. There is no generic write endpoint.
 */

// Session & staff
export const adminGetMyStaffProfile = defineAdminCommand(specs.adminGetMyStaffProfileSpec);
export const adminRecordLogin = defineAdminCommand(specs.adminRecordLoginSpec);
export const adminGetDashboard = defineAdminCommand(specs.adminGetDashboardSpec);
export const adminListStaff = defineAdminCommand(specs.adminListStaffSpec);
export const adminGetStaff = defineAdminCommand(specs.adminGetStaffSpec);
export const adminCreateStaff = defineAdminCommand(specs.adminCreateStaffSpec);
export const adminIssueStaffActivation = defineAdminCommand(specs.adminIssueStaffActivationSpec);
export const adminRevokeStaffSessions = defineAdminCommand(specs.adminRevokeStaffSessionsSpec);
export const adminUpdateStaffRole = defineAdminCommand(specs.adminUpdateStaffRoleSpec);
export const adminDisableStaff = defineAdminCommand(specs.adminDisableStaffSpec);
export const adminEnableStaff = defineAdminCommand(specs.adminEnableStaffSpec);

// App Control
export const adminGetAppControl = defineAdminCommand(specs.adminGetAppControlSpec);
export const adminUpdateMaintenanceMode = defineAdminCommand(specs.adminUpdateMaintenanceModeSpec);
export const adminUpdateMinimumVersion = defineAdminCommand(specs.adminUpdateMinimumVersionSpec);
export const adminUpdateFeatureSwitch = defineAdminCommand(specs.adminUpdateFeatureSwitchSpec);
export const adminUpdateAnnouncement = defineAdminCommand(specs.adminUpdateAnnouncementSpec);

// Users
export const adminSearchUsers = defineAdminCommand(specs.adminSearchUsersSpec);
export const adminGetUserOverview = defineAdminCommand(specs.adminGetUserOverviewSpec);
export const adminGetUserSafetyTimeline = defineAdminCommand(specs.adminGetUserSafetyTimelineSpec);
export const adminWarnUser = defineAdminCommand(specs.adminWarnUserSpec);
export const adminSuspendUser = defineAdminCommand(specs.adminSuspendUserSpec);
export const adminBanUser = defineAdminCommand(specs.adminBanUserSpec);
export const adminRestoreUser = defineAdminCommand(specs.adminRestoreUserSpec);

// Cases
export const adminListCases = defineAdminCommand(specs.adminListCasesSpec);
export const adminGetCase = defineAdminCommand(specs.adminGetCaseSpec);
export const adminOpenCase = defineAdminCommand(specs.adminOpenCaseSpec);
export const adminAssignCase = defineAdminCommand(specs.adminAssignCaseSpec);
export const adminSetCaseStatus = defineAdminCommand(specs.adminSetCaseStatusSpec);
export const adminResolveCase = defineAdminCommand(specs.adminResolveCaseSpec);
export const adminEscalateCase = defineAdminCommand(specs.adminEscalateCaseSpec);
export const adminAddCaseNote = defineAdminCommand(specs.adminAddCaseNoteSpec);

// Reports
export const adminListReports = defineAdminCommand(specs.adminListReportsSpec);
export const adminResolveUserReport = defineAdminCommand(specs.adminResolveUserReportSpec);
export const adminOpenReportCase = defineAdminCommand(specs.adminOpenReportCaseSpec);

// Photos
export const adminListPhotoReviews = defineAdminCommand(specs.adminListPhotoReviewsSpec);
export const adminGetPhotoPreview = defineAdminCommand(specs.adminGetPhotoPreviewSpec);
export const adminReviewPhoto = defineAdminCommand(specs.adminReviewPhotoSpec);

// Humor
export const adminListHumorReviews = defineAdminCommand(specs.adminListHumorReviewsSpec);
export const adminGetHumorReports = defineAdminCommand(specs.adminGetHumorReportsSpec);
export const adminReviewHumorContent = defineAdminCommand(specs.adminReviewHumorContentSpec);

// Verification (read, escalate, require again — never "mark verified")
export const adminGetVerification = defineAdminCommand(specs.adminGetVerificationSpec);
export const adminListVerificationReviews = defineAdminCommand(specs.adminListVerificationReviewsSpec);
export const adminRequireReverification = defineAdminCommand(specs.adminRequireReverificationSpec);
export const adminEscalateVerification = defineAdminCommand(specs.adminEscalateVerificationSpec);

// Support
export const adminListSupportTickets = defineAdminCommand(specs.adminListSupportTicketsSpec);
export const adminGetSupportTicket = defineAdminCommand(specs.adminGetSupportTicketSpec);
export const adminGetSupportAttachment = defineAdminCommand(specs.adminGetSupportAttachmentSpec);
export const adminAssignSupportTicket = defineAdminCommand(specs.adminAssignSupportTicketSpec);
export const adminReplySupportTicket = defineAdminCommand(specs.adminReplySupportTicketSpec);
export const adminAddSupportNote = defineAdminCommand(specs.adminAddSupportNoteSpec);
export const adminUpdateSupportTicket = defineAdminCommand(specs.adminUpdateSupportTicketSpec);
export const adminResolveSupportTicket = defineAdminCommand(specs.adminResolveSupportTicketSpec);
export const adminEscalateSupportTicket = defineAdminCommand(specs.adminEscalateSupportTicketSpec);

// Automation
export const adminListManualReviewJobs = defineAdminCommand(specs.adminListManualReviewJobsSpec);
export const adminReviewAutomationJob = defineAdminCommand(specs.adminReviewAutomationJobSpec);
export const adminResolveReviewItem = defineAdminCommand(specs.adminResolveReviewItemSpec);

// Appeals
export const adminListAppeals = defineAdminCommand(specs.adminListAppealsSpec);
export const adminGetAppeal = defineAdminCommand(specs.adminGetAppealSpec);
export const adminAssignAppeal = defineAdminCommand(specs.adminAssignAppealSpec);
export const adminResolveAppeal = defineAdminCommand(specs.adminResolveAppealSpec);
export const adminOpenAppeal = defineAdminCommand(specs.adminOpenAppealSpec);

// Audit & maintenance
export const adminListAuditEvents = defineAdminCommand(specs.adminListAuditEventsSpec);
export const adminBackfillReportPriority = defineAdminCommand(specs.adminBackfillReportPrioritySpec);
export const adminRebuildUserLookup = defineAdminCommand(specs.adminRebuildUserLookupSpec);

// Member-facing side of moderation (App Check enforced).
export {getMyModerationStatus, submitModerationAppeal} from "./appeals/consumerAppeals.js";

/** Keeps adminUserLookup/{uid} in step with the profile's display name. */
export const syncAdminUserLookup = onDocumentWritten(
  {document: "profiles/{uid}", region: ADMIN_REGION},
  async (event) => {
    await syncLookupForProfile(
      getFirestore(),
      event.params.uid,
      event.data?.before?.data(),
      event.data?.after?.data(),
    );
  },
);

export const adminSuspensionExpirySweep = onSchedule(
  {schedule: "every 60 minutes", region: ADMIN_REGION},
  async () => {
    const expired = await expireSuspensions(getFirestore(), Date.now());
    logger.info("admin_suspension_expiry_sweep", {expired});
  },
);

export const adminRetentionSweep = onSchedule(
  {schedule: "every 24 hours", region: ADMIN_REGION},
  async () => {
    await runRetentionSweep(
      getFirestore(),
      () => getStorage().bucket() as unknown as AdminBucketPort,
      Date.now(),
      process.env.ADMIN_RETENTION_ENFORCE === "true",
    );
  },
);
