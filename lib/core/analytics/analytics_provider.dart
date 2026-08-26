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
  static const String boostActivated = 'boost_activated';
  static const String boostExpired = 'boost_expired';
  static const String compatibilityViewed = 'compatibility_viewed';
  static const String whyYouMatchOpened = 'why_you_match_opened';
  static const String hiddenCompatibilitySeen = 'hidden_compatibility_seen';
  static const String hiddenCompatibilityClicked = 'hidden_compatibility_clicked';
  static const String compatibilityMatchCreated = 'compatibility_match_created';
}

abstract class AnalyticsProvider {
  Future<void> logEvent(String name, {Map<String, Object>? parameters});

  Future<void> setUserId(String? userId);
}
