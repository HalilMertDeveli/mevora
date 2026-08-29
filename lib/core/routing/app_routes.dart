abstract final class AppRoutes {
  static const String splash = '/';
  static const String root = splash;
  static const String login = '/login';
  static const String register = '/register';
  static const String passwordReset = '/password-reset';
  static const String onboarding = '/onboarding';
  static const String locationPermission = '/onboarding/location';
  static const String discovery = '/discovery';
  static const String matches = '/matches';
  static const String music = '/music';
  static const String humorLab = '/humor-lab';
  static const String profile = '/profile';
  static const String chat = '/chat/:matchId';
  static const String incomingCall = '/call/incoming/:callId';
  static const String videoCall = '/call/video/:callId';
  static const String report = '/safety/report';
  static const String designSystem = '/debug/design-system';
  static const String phone = '/phone';
  static const String phoneOtp = '/phone/otp';
  static const String settings = '/settings';
  static const String editProfile = '/settings/edit-profile';
  static const String profileAnswers = '/settings/profile-answers';
  static const String changePassword = '/settings/change-password';
  static const String discoveryPreferences = '/settings/discovery-preferences';
  static const String locationSettings = '/settings/location';
  static const String privacySettings = '/settings/privacy-controls';
  static const String blockedUsers = '/settings/blocked-users';
  static const String notificationSettings = '/settings/notifications';
  static const String privacyPermissions = '/settings/privacy';
  static const String accountSettings = '/settings/account';
  static const String boost = '/boost';
  static const String premium = '/premium';
  static const String likesYou = '/likes-you';

  static const String verifyProfile = '/settings/verify-profile';

  static const String supportCenter = '/settings/support';
  static const String supportFaq = '/settings/support/faq';
  static const String supportTicketCreate = '/settings/support/ticket/create';
  static const String supportTickets = '/settings/support/tickets';
  static const String supportTicketDetail = '/settings/support/tickets/:ticketId';
  static const String communityGuidelines = '/settings/support/guidelines';
  static const String termsOfService = '/settings/support/terms';
  static const String privacyPolicy = '/settings/support/privacy';

  static const String legalTerms = '/legal/terms';
  static const String legalPrivacy = '/legal/privacy';
  static const String legalGuidelines = '/legal/guidelines';

  static String supportTicketDetailPath(String ticketId) =>
      '/settings/support/tickets/$ticketId';

  static String chatPath(String matchId) => '/chat/$matchId';

  static String incomingCallPath(String callId) => '/call/incoming/$callId';

  static String videoCallPath(String callId) => '/call/video/$callId';
}
