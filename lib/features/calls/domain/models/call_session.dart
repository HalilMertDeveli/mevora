enum CallLifecycle {
  idle,
  calling,
  ringing,
  connecting,
  connected,
  reconnecting,
  ended,
  declined,
  cancelled,
  busy,
  failed,
}

enum CallEvent {
  startOutgoing,
  receiveIncoming,
  accept,
  decline,
  cancel,
  remoteAccepted,
  remoteDeclined,
  connected,
  connectionLost,
  reconnected,
  end,
  fail,
  busy,
  timeout,
}

enum CallHistoryStatus { completed, declined, missed, failed, cancelled }

class CallSession {
  const CallSession({
    required this.id,
    required this.matchId,
    required this.callerId,
    required this.receiverId,
    required this.lifecycle,
    required this.createdAt,
    this.livekitUrl,
    this.token,
    this.roomName,
    this.remoteName,
    this.remotePhotoUrl,
  });

  final String id;
  final String matchId;
  final String callerId;
  final String receiverId;
  final CallLifecycle lifecycle;
  final DateTime createdAt;
  final String? livekitUrl;
  final String? token;
  final String? roomName;
  final String? remoteName;
  final String? remotePhotoUrl;

  bool isIncomingFor(String uid) => receiverId == uid;

  CallSession copyWith({
    CallLifecycle? lifecycle,
    String? livekitUrl,
    String? token,
    String? roomName,
  }) {
    return CallSession(
      id: id,
      matchId: matchId,
      callerId: callerId,
      receiverId: receiverId,
      lifecycle: lifecycle ?? this.lifecycle,
      createdAt: createdAt,
      livekitUrl: livekitUrl ?? this.livekitUrl,
      token: token ?? this.token,
      roomName: roomName ?? this.roomName,
      remoteName: remoteName,
      remotePhotoUrl: remotePhotoUrl,
    );
  }
}

class CallHistoryRecord {
  const CallHistoryRecord({
    required this.id,
    required this.callerId,
    required this.receiverId,
    required this.matchId,
    required this.type,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
  });

  final String id;
  final String callerId;
  final String receiverId;
  final String matchId;
  final String type;
  final CallHistoryStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
}
