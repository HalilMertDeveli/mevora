/// Canonical Firestore / Storage paths. Identity keys are Firebase UIDs only.
abstract final class FirestorePaths {
  static const String users = 'users';
  static const String profiles = 'profiles';
  static const String userPreferences = 'userPreferences';
  static const String userSettings = 'userSettings';
  static const String userPrivacy = 'userPrivacy';
  static const String userLocation = 'userLocation';
  static const String likes = 'likes';
  static const String matches = 'matches';
  static const String notifications = 'notifications';
  static const String reports = 'reports';
  static const String calls = 'calls';
  static const String callHistory = 'callHistory';
  static const String blocks = 'blocks';
  static const String purchases = 'purchases';
  static const String boosts = 'boosts';

  static const String devices = 'devices';
  static const String blockedUsers = 'blockedUsers';
  static const String messages = 'messages';
  static const String fcmTokens = 'fcmTokens';

  static String user(String uid) => '$users/$uid';

  static String profile(String uid) => '$profiles/$uid';

  static String preferences(String uid) => '$userPreferences/$uid';

  static String settings(String uid) => '$userSettings/$uid';

  static String privacy(String uid) => '$userPrivacy/$uid';

  static String location(String uid) => '$userLocation/$uid';

  static String like(String likeId) => '$likes/$likeId';

  static String match(String matchId) => '$matches/$matchId';

  static String matchMessages(String matchId) => '$matches/$matchId/$messages';

  static String matchMessage(String matchId, String messageId) =>
      '$matches/$matchId/$messages/$messageId';

  static String matchTyping(String matchId) => '$matches/$matchId/meta/typing';

  static String notification(String notificationId) =>
      '$notifications/$notificationId';

  static String report(String reportId) => '$reports/$reportId';

  static String call(String callId) => '$calls/$callId';

  static String device(String uid, String deviceId) =>
      '$users/$uid/$devices/$deviceId';

  static String blockedUser(String uid, String blockedUserId) =>
      '$users/$uid/$blockedUsers/$blockedUserId';

  /// Legacy top-level block id (`{blockerId}_{blockedUserId}`).
  static String block(String blockId) => '$blocks/$blockId';

  static String fcmToken(String uid, String tokenId) =>
      '$users/$uid/$fcmTokens/$tokenId';

  static String notificationSettings(String uid) =>
      '$users/$uid/settings/notifications';

  static String presence(String uid) => '$users/$uid/presence/current';

  static String purchase(String purchaseId) => '$purchases/$purchaseId';

  static String userBoosts(String uid) => '$users/$uid/$boosts';

  static String userBoost(String uid, String boostId) =>
      '$users/$uid/$boosts/$boostId';
}

abstract final class StoragePaths {
  static const int maxProfileImageBytes = 5 * 1024 * 1024;

  static const Set<String> allowedImageContentTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  static String profilePending({
    required String ownerUid,
    required String imageId,
  }) => 'users/$ownerUid/profile/pending/$imageId';

  /// Canonical client upload path. Unique [imageId] so photos are never overwritten.
  static String profilePhoto({
    required String ownerUid,
    required String imageId,
    String extension = 'jpg',
  }) => 'users/$ownerUid/profile/photos/$imageId.$extension';

  static String profileApproved({
    required String ownerUid,
    required String imageId,
  }) => 'users/$ownerUid/profile/$imageId';

  static String profileThumb({
    required String ownerUid,
    required String imageId,
  }) => 'users/$ownerUid/profile/thumbs/$imageId';

  static String chatImage({
    required String ownerUid,
    required String matchId,
    required String messageId,
  }) {
    return 'users/$ownerUid/chat/$matchId/$messageId';
  }
}
