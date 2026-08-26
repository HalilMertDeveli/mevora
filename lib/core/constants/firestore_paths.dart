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
  static const String boostWallet = 'boostWallet';
  static const String boostProducts = 'boostProducts';
  static const String subscription = 'subscription';
  static const String supportTickets = 'supportTickets';

  static const String devices = 'devices';
  static const String blockedUsers = 'blockedUsers';
  static const String messages = 'messages';
  static const String fcmTokens = 'fcmTokens';
  static const String scoreHistory = 'matchScoreHistory';
  static const String matchFeedback = 'matchFeedback';
  static const String pendingFeedback = 'pendingMatchFeedback';
  static const String relationshipAnswers = 'relationshipAnswers';
  static const String relationshipMatch = 'relationshipMatch';
  static const String relationshipSeen = 'relationshipSeen';
  static const String questionAnswers = 'questionAnswers';

  static String supportTicket(String ticketId) => '$supportTickets/$ticketId';

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

  static String subscriptionCurrent(String uid) =>
      '$users/$uid/$subscription/current';

  static String matchScoreHistory(String uid) => '$users/$uid/$scoreHistory';

  static String matchFeedbackDoc(String uid, String matchId) =>
      '$users/$uid/$matchFeedback/$matchId';

  static String pendingMatchFeedback(String uid) =>
      '$users/$uid/$pendingFeedback';

  static String purchase(String purchaseId) => '$purchases/$purchaseId';

  static String userBoosts(String uid) => '$users/$uid/$boosts';

  static String userBoost(String uid, String boostId) =>
      '$users/$uid/$boosts/$boostId';

  static String userBoostWallet(String uid) =>
      '$users/$uid/$boostWallet/current';

  static String boostProduct(String productId) => '$boostProducts/$productId';

  static String relationshipAnswer(String uid, String questionId) =>
      '$users/$uid/$relationshipAnswers/$questionId';

  static String relationshipMatchSummary(String uid) =>
      '$users/$uid/$relationshipMatch/summary';

  static String relationshipSeenDoc(String uid, String otherUid) =>
      '$users/$uid/$relationshipSeen/$otherUid';

  static String questionAnswer(String uid, String questionId) =>
      '$users/$uid/$questionAnswers/$questionId';

  static String userQuestionAnswers(String uid) =>
      '$users/$uid/$questionAnswers';
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
    String extension = 'jpg',
  }) => 'users/$ownerUid/profile/pending/$imageId.$extension';

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
    String extension = 'jpg',
  }) {
    return 'users/$ownerUid/chat/$matchId/$messageId.$extension';
  }

  static String chatVoice({
    required String ownerUid,
    required String matchId,
    required String messageId,
    String extension = 'm4a',
  }) {
    return 'users/$ownerUid/chat/$matchId/$messageId.$extension';
  }

  static const int maxChatImageBytes = 5 * 1024 * 1024;
  static const int maxChatVoiceBytes = 8 * 1024 * 1024;
  /// Matches `isEncryptedChatBlob()` in `firebase/storage.rules`.
  static const int maxChatEncryptedBytes = 25 * 1024 * 1024;

  static const Set<String> allowedChatAudioTypes = {
    'audio/mp4',
    'audio/m4a',
    'audio/x-m4a',
    'audio/aac',
    'audio/mpeg',
  };

  static const String encryptedChatContentType = 'application/octet-stream';

  /// Client-side gate aligned with Storage rules for chat media uploads.
  static bool isAllowedChatUpload({
    required String contentType,
    required int sizeBytes,
  }) {
    if (sizeBytes <= 0) {
      return false;
    }
    final lower = contentType.toLowerCase().trim();
    if (allowedChatAudioTypes.contains(lower)) {
      return sizeBytes <= maxChatVoiceBytes;
    }
    if (lower == encryptedChatContentType) {
      return sizeBytes <= maxChatEncryptedBytes;
    }
    const images = {
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
    };
    return images.contains(lower) && sizeBytes <= maxChatImageBytes;
  }

  static const int maxSupportAttachmentBytes = 5 * 1024 * 1024;

  static String supportAttachment({
    required String ownerUid,
    required String ticketId,
    required String fileName,
  }) => 'users/$ownerUid/support/$ticketId/$fileName';
}
