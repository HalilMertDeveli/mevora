export * from "./backend";
export * from "./social";
export * from "./matchScore";
export * from "./notifications";
export * from "./incomingLikes";
export * from "./premium";
export {completeOnboarding} from "./onboarding";
export {profileAgeRollover} from "./profileAgeRollover.js";
export {enforceProfilePhotoModeration} from "./moderation/profileModerationGuard.js";
export {deleteProfilePhoto} from "./moderation/deleteProfilePhotoFunction.js";
export {profilePhotoOrphanSweep} from "./moderation/photoOrphanSweepFunction.js";
export {spotifyCompleteAuth} from "./spotifyAuth";
export {
  spotifyLinkMusic,
  getMusicAccount,
  updatePublicMusicProfile,
  syncSpotifyTaste,
  disconnectMusicAccount,
  getSameTasteProfiles,
  getWeeklyMusicStats,
  aggregateWeeklyMusicStats,
  getMatchMusicCompatibility,
} from "./spotifyMusic.js";
export {
  saveRelationshipAnswer,
  getRelationshipAnswered,
  syncProfileQuestionAnswers,
  updateQuestionAnswerVisibility,
} from "./relationshipMatch";
export {verifyBoostPurchase, activateBoost, expireBoost} from "./boost/verifyBoostPurchase.js";
export {reconcileVoidedBoostPurchases} from "./boost/voidedPurchaseSweep.js";
export {verifyPremiumPurchase} from "./subscription/verifyPremiumPurchase.js";
export {onPlaySubscriptionNotification} from "./subscription/googleRtdnFunction.js";
export {getMevoraPicks} from "./picks/index.js";
export {recordDailyCheckIn} from "./streak/index.js";
export {
  createIdentityVerificationSession,
  getIdentityVerificationState,
} from "./identity/createIdentityVerificationSession.js";
export {identityVerificationWebhook} from "./identity/identityVerificationWebhook.js";
// Face Anchor: is this profile photo the live account owner? Separate from
// identity verification above, which answers who the account owner is.
export {
  getFaceAnchorRequirements,
  startFaceAnchorVerification,
  submitFaceAnchorVerification,
  faceAnchorSelfieSweep,
} from "./faceAnchor/functions.js";
export {
  getHumorFeed,
  submitHumorFeedback,
  getHumorProfile,
  getMatchHumorCompatibility,
  reportHumorContent,
  upsertHumorContent,
  runHumorModeration,
  getHumorCalibrationPoolReport,
  seedInternalHumorContent,
  syncHumorFromProvider,
  getDailyHumorSet,
  submitDailyHumorResponse,
} from "./humor/index.js";
export {
  personalizationOnDecision,
  personalizationOnMatchCreated,
  recordProfileEngagement,
  resetMyPersonalization,
} from "./personalization/functions.js";
export {
  getRelationshipLearningState,
  saveDailyRelationshipAnswer,
  skipOnboardingHumor,
  skipTodayRelationshipQuestions,
  updateRelationshipAnswer,
} from "./relationshipLearning/functions.js";

// Automation job processors. `deleteUserAccount` enqueues an
// `accountDeletionVerify` job (plus a Cloud Task); without these exports the
// task queue target does not exist and nothing drains `automationJobs`, so the
// job stays `queued` forever.
export {processAutomationTask, automationJobDrain} from "./automation/schedules.js";
// Admin-only, read-only B-01 follow-up audit (never mutates blocks).
export {runForgedBlockAudit} from "./automation/forgedBlockAuditCallable.js";
// Admin / Trust & Safety control plane: explicit staff commands (RBAC + MFA +
// audit), the member's appeal callables, and T&S upkeep. See
// docs/ADMIN_TRUST_SAFETY_ARCHITECTURE.md.
export * from "./admin/index.js";

// Emulator-only callables: the smoke users, the GIPHY curator search and the
// personalization debugger (see emulatorOnly.ts). They are added to the
// exports only when this process is the Functions emulator. A deploy loads
// this file without FUNCTIONS_EMULATOR to discover what to ship, so none of
// them is deployed, and the require is inside the condition so their modules
// (and the smoke secret) are not loaded there either. Never export a QA or
// debugging callable above this line.
if (process.env.FUNCTIONS_EMULATOR === "true") {
  Object.assign(exports, require("./emulatorOnly.js"));
}
