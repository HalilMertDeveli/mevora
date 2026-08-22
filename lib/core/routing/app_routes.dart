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
  static const String changePassword = '/settings/change-password';
  static const String discoveryPreferences = '/settings/discovery-preferences';
  static const String locationSettings = '/settings/location';
  static const String privacySettings = '/settings/privacy-controls';
  static const String blockedUsers = '/settings/blocked-users';
  static const String notificationSettings = '/settings/notifications';
  static const String privacyPermissions = '/settings/privacy';
  static const String boost = '/boost';

  static String chatPath(String matchId) => '/chat/$matchId';

  static String incomingCallPath(String callId) => '/call/incoming/$callId';

  static String videoCallPath(String callId) => '/call/video/$callId';
}
