class UserSettings {
  const UserSettings({
    required this.uid,
    this.languageCode = 'en',
    this.theme = 'system',
    this.notificationsEnabled = true,
    this.messageNotifications = true,
    this.matchNotifications = true,
    this.callNotifications = true,
    this.locationEnabled = false,
    this.locationOnboardingCompleted = false,
    this.lastLocationUpdate,
    this.showOnlineStatus = true,
  });

  final String uid;

  /// Canonical UI language: `tr` or `en`.
  final String languageCode;

  /// Alias kept for code that still reads [language].
  String get language => languageCode;
  final String theme;
  final bool notificationsEnabled;
  final bool messageNotifications;
  final bool matchNotifications;
  final bool callNotifications;
  final bool locationEnabled;
  final bool locationOnboardingCompleted;
  final DateTime? lastLocationUpdate;
  final bool showOnlineStatus;

  UserSettings copyWith({
    String? uid,
    String? languageCode,
    String? theme,
    bool? notificationsEnabled,
    bool? messageNotifications,
    bool? matchNotifications,
    bool? callNotifications,
    bool? locationEnabled,
    bool? locationOnboardingCompleted,
    DateTime? lastLocationUpdate,
    bool? showOnlineStatus,
  }) {
    return UserSettings(
      uid: uid ?? this.uid,
      languageCode: languageCode ?? this.languageCode,
      theme: theme ?? this.theme,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      messageNotifications: messageNotifications ?? this.messageNotifications,
      matchNotifications: matchNotifications ?? this.matchNotifications,
      callNotifications: callNotifications ?? this.callNotifications,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      locationOnboardingCompleted:
          locationOnboardingCompleted ?? this.locationOnboardingCompleted,
      lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
    );
  }
}

class UserPrivacy {
  const UserPrivacy({
    required this.uid,
    this.showOnlineStatus = true,
    this.showDistance = true,
    this.showAge = true,
    this.allowNotifications = true,
    this.allowCalls = true,
    this.allowMessages = true,
  });

  final String uid;
  final bool showOnlineStatus;
  final bool showDistance;
  final bool showAge;
  final bool allowNotifications;
  final bool allowCalls;
  final bool allowMessages;
}
