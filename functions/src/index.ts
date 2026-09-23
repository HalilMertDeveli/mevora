export * from "./backend";
export * from "./social";
export * from "./matchScore";
export * from "./notifications";
export * from "./incomingLikes";
export * from "./premium";
export {completeOnboarding} from "./onboarding";
export {enforceProfilePhotoModeration} from "./moderation/profileModerationGuard.js";
export {prepareSmokeTestUsers, cleanupSmokeTestUsers} from "./smoke/smokeTestUsers.js";
export {spotifyCompleteAuth} from "./spotifyAuth";
export {
  spotifyLinkMusic,
  getMusicAccount,
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
  getRelationshipMatches,
  completeRelationshipTest,
  dismissRelationshipTestOffer,
  syncProfileQuestionAnswers,
  updateQuestionAnswerVisibility,
} from "./relationshipMatch";
export {verifyBoostPurchase, activateBoost, expireBoost} from "./boost/verifyBoostPurchase.js";
export {createSumsubAccessToken, sumsubWebhook} from "./sumsub/index.js";
export {
  createIdentityVerificationSession,
  getIdentityVerificationState,
} from "./identity/createIdentityVerificationSession.js";
export {identityVerificationWebhook} from "./identity/identityVerificationWebhook.js";
export {
  getHumorFeed,
  submitHumorFeedback,
  getHumorProfile,
  getMatchHumorCompatibility,
  reportHumorContent,
  upsertHumorContent,
  runHumorModeration,
  seedInternalHumorContent,
  syncHumorFromProvider,
} from "./humor/index.js";

// Automation job processors. `deleteUserAccount` enqueues an
// `accountDeletionVerify` job (plus a Cloud Task); without these exports the
// task queue target does not exist and nothing drains `automationJobs`, so the
// job stays `queued` forever.
export {processAutomationTask, automationJobDrain} from "./automation/schedules.js";
// Admin-only, read-only B-01 follow-up audit (never mutates blocks).
export {runForgedBlockAudit} from "./automation/forgedBlockAuditCallable.js";
