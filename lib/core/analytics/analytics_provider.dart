/// Product analytics event names. Never include email, phone, exact GPS,
/// passwords, or tokens in parameters.
abstract final class AnalyticsEvents {
  static const String appOpen = 'app_open';
  static const String signUp = 'sign_up';
  static const String login = 'login';
  static const String logout = 'logout';
  static const String profileCompleted = 'profile_completed';
  static const String onboardingCompleted = 'onboarding_completed';
  static const String profileUpdated = 'profile_updated';
  static const String like = 'like';
  static const String swipeLike = 'swipe_like';
  static const String swipePass = 'swipe_pass';
  static const String swipeSuperLike = 'swipe_super_like';
  static const String match = 'match';
  static const String matchCreated = 'match_created';
  static const String message = 'message';
  static const String messageSent = 'message_sent';
  static const String videoCall = 'video_call';
  static const String reportSubmitted = 'report_submitted';
  static const String userBlocked = 'user_blocked';
  static const String accountDeleted = 'account_deleted';
  static const String callStarted = 'call_started';
  static const String callEnded = 'call_ended';
  static const String locationPermissionRequested =
      'location_permission_requested';
  static const String locationPermissionGranted = 'location_permission_granted';
  static const String locationPermissionDenied = 'location_permission_denied';
  static const String locationPermissionDeniedForever =
      'location_permission_denied_forever';
  static const String locationServicesDisabled = 'location_services_disabled';
  static const String locationAcquired = 'location_acquired';
  static const String locationError = 'location_error';
  static const String boostViewed = 'boost_viewed';
  static const String boostPageOpened = 'boost_page_opened';
  static const String boostProductSelected = 'boost_product_selected';
  static const String boostPurchaseStarted = 'boost_purchase_started';
  static const String boostPurchaseSuccess = 'boost_purchase_success';
  static const String boostPurchaseCancelled = 'boost_purchase_cancelled';
  static const String boostPurchaseFailed = 'boost_purchase_failed';

  // Premium. Deliberately carries no purchase token, receipt, JWS or price:
  // the funnel is what these answer, and a token in an analytics payload is
  // a credential leaving the device.
  static const String premiumPaywallViewed = 'premium_paywall_viewed';
  static const String premiumPurchaseStarted = 'premium_purchase_started';
  static const String premiumPurchasePending = 'premium_purchase_pending';
  static const String premiumPurchaseSuccess = 'premium_purchase_success';
  static const String premiumPurchaseCancelled = 'premium_purchase_cancelled';
  static const String premiumPurchaseFailed = 'premium_purchase_failed';
  static const String premiumRestoreStarted = 'premium_restore_started';
  static const String premiumRestoreSuccess = 'premium_restore_success';
  static const String premiumEntitlementChanged = 'premium_entitlement_changed';
  static const String boostActivated = 'boost_activated';
  static const String boostExpired = 'boost_expired';
  static const String compatibilityViewed = 'compatibility_viewed';
  static const String whyYouMatchOpened = 'why_you_match_opened';
  static const String hiddenCompatibilitySeen = 'hidden_compatibility_seen';
  static const String hiddenCompatibilityClicked = 'hidden_compatibility_clicked';
  static const String compatibilityMatchCreated = 'compatibility_match_created';
  // Mevora Picks funnel. Params: pick_type, pick_id (opaque, never a uid),
  // generation_id, position, score_bucket, source. Mutual match, conversation
  // started and survived-24h are also counted server-side in pickFunnelDaily.
  static const String pickDelivered = 'pick_delivered';
  static const String pickImpression = 'pick_impression';
  static const String pickProfileOpen = 'pick_profile_open';
  static const String pickLike = 'pick_like';
  static const String pickPass = 'pick_pass';
  static const String pickMutualMatch = 'pick_mutual_match';
  // Daily streak. Only credited days are logged, never a same-day reopen.
  // Params: status, streak_length_bucket, personal_best — no uid or dates.
  static const String streakCheckIn = 'streak_check_in';
  static const String streakPersonalBest = 'streak_personal_best';
  static const String streakDetailsViewed = 'streak_details_viewed';
  // Today's finite set ran out: {reason}. Never a uid.
  static const String dailyPicksExhausted = 'daily_picks_exhausted';
  // Relationship Learning. Params: {source}, {stage: initial|follow_up},
  // {dimension}, {position}. Never an answer: what someone chose stays theirs.
  static const String relationshipLearningStarted =
      'relationship_learning_started';
  static const String relationshipLearningQuestionAnswered =
      'relationship_learning_question_answered';
  static const String relationshipLearningInitialCompleted =
      'relationship_learning_initial_completed';
  static const String relationshipLearningFollowUpStarted =
      'progressive_questions_started';
  static const String relationshipLearningFollowUpCompleted =
      'progressive_questions_completed';
  static const String relationshipLearningFollowUpSnoozed =
      'progressive_questions_snoozed';
  // The interaction-learning switch and the reset. No parameters.
  static const String personalizationEnabled = 'personalization_enabled';
  static const String personalizationDisabled = 'personalization_disabled';
  static const String personalizationReset = 'personalization_reset';
  static const String spotifyConnectStarted = 'spotify_connect_started';
  static const String spotifyConnectSuccess = 'spotify_connect_success';
  static const String spotifyConnectFailed = 'spotify_connect_failed';
  static const String spotifyDisconnected = 'spotify_disconnected';
  static const String spotifySyncStarted = 'spotify_sync_started';
  static const String spotifySyncSuccess = 'spotify_sync_success';
  static const String spotifySyncFailed = 'spotify_sync_failed';
  static const String musicCompatibilityViewed = 'music_compatibility_viewed';
  static const String commonTracksViewed = 'common_tracks_viewed';
  static const String musicInsightsUnlocked = 'music_insights_unlocked';
  static const String humorLabOpened = 'humor_lab_opened';
  static const String humorContentViewed = 'humor_content_viewed';
  static const String humorContentRated = 'humor_content_rated';
  static const String humorContentSkipped = 'humor_content_skipped';
  static const String humorContentReplayed = 'humor_content_replayed';
  static const String humorContentSaved = 'humor_content_saved';
  // Humor media reliability: {reason, attempt}, {kind}, {reason}. Never a URL.
  static const String humorMediaFailed = 'humor_media_failed';
  static const String humorMediaRetry = 'humor_media_retry';
  static const String humorMediaSkipped = 'humor_media_skipped';
  // Initial calibration milestone. Stage and counts only — a humor vector is
  // behavioural data and must never reach analytics.
  static const String humorCalibrationImpression =
      'humor_calibration_impression';
  static const String humorCalibrationStarted = 'humor_calibration_started';
  static const String humorCalibrationSkipped = 'humor_calibration_skipped';
  static const String humorCalibrationProgress = 'humor_calibration_progress';
  static const String humorCalibrationCompleted = 'humor_calibration_completed';
  static const String humorProfileViewed = 'humor_profile_viewed';
  static const String humorCompatibilityViewed = 'humor_compatibility_viewed';
  static const String humorChatStarterShown = 'humor_chat_starter_shown';
  static const String humorChatStarterUsed = 'humor_chat_starter_used';
}

abstract class AnalyticsProvider {
  Future<void> logEvent(String name, {Map<String, Object>? parameters});

  Future<void> setUserId(String? userId);
}
