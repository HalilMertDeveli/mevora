class NotificationPrefs {
  const NotificationPrefs({
    this.messageNotifications = true,
    this.matchNotifications = true,
    this.mevoraHourReminders = false,
    this.hideOnlineStatus = false,
  });

  final bool messageNotifications;
  final bool matchNotifications;

  /// Opt-in only: FCM when a Mevora Hour round opens (Europe/Istanbul).
  final bool mevoraHourReminders;
  final bool hideOnlineStatus;

  NotificationPrefs copyWith({
    bool? messageNotifications,
    bool? matchNotifications,
    bool? mevoraHourReminders,
    bool? hideOnlineStatus,
  }) {
    return NotificationPrefs(
      messageNotifications: messageNotifications ?? this.messageNotifications,
      matchNotifications: matchNotifications ?? this.matchNotifications,
      mevoraHourReminders: mevoraHourReminders ?? this.mevoraHourReminders,
      hideOnlineStatus: hideOnlineStatus ?? this.hideOnlineStatus,
    );
  }
}

enum PushType { message, match, incomingCall, missedCall, mevoraHour }

class PushPayload {
  const PushPayload({
    required this.type,
    this.matchId,
    this.callId,
    this.preview,
    this.roundId,
  });

  final PushType type;
  final String? matchId;
  final String? callId;
  final String? preview;
  final String? roundId;

  static PushPayload? fromData(Map<String, dynamic> data) {
    final raw = data['type'] as String?;
    final type = switch (raw) {
      'newMessage' || 'message' => PushType.message,
      'newMatch' || 'match' => PushType.match,
      'incomingCall' || 'incoming_call' => PushType.incomingCall,
      'missedCall' || 'missed_call' => PushType.missedCall,
      'mevoraHourLive' || 'mevora_hour_live' => PushType.mevoraHour,
      _ => null,
    };
    if (type == null) {
      return null;
    }
    return PushPayload(
      type: type,
      matchId: data['matchId'] as String?,
      callId: data['callId'] as String?,
      preview: data['preview'] as String?,
      roundId: data['roundId'] as String?,
    );
  }
}

abstract class NotificationRepository {
  Stream<NotificationPrefs> watchPrefs(String uid);

  Future<NotificationPrefs> loadPrefs(String uid);

  Future<void> savePrefs(String uid, NotificationPrefs prefs);

  Future<void> registerToken(String uid, String token);

  Future<void> unregisterToken(String uid, String token);
}
