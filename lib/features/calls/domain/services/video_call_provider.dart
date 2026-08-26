import 'package:mevora/features/calls/domain/models/call_session.dart';

class VideoConnectParams {
  const VideoConnectParams({
    required this.url,
    required this.token,
    required this.roomName,
  });

  final String url;
  final String token;
  final String roomName;
}

enum VideoConnectionQuality { good, unstable, lost }

class VideoConnectionEvent {
  const VideoConnectionEvent({
    required this.lifecycleHint,
    required this.quality,
    required this.remoteVideoAvailable,
    required this.localVideoEnabled,
    this.errorCode,
  });

  final CallLifecycle lifecycleHint;
  final VideoConnectionQuality quality;
  final bool remoteVideoAvailable;
  final bool localVideoEnabled;

  /// Internal only — never shown to users.
  final String? errorCode;
}

/// SDK-agnostic media connection. Swap LiveKit/Agora by implementing this.
abstract class VideoCallProvider {
  Future<void> connect(VideoConnectParams params);

  Future<void> disconnect();

  Future<void> setMicrophoneEnabled(bool enabled);

  Future<void> setCameraEnabled(bool enabled);

  Future<void> switchCamera();

  Future<void> setSpeakerEnabled(bool enabled);

  Stream<VideoConnectionEvent> watch();

  bool get isMicrophoneEnabled;

  bool get isCameraEnabled;

  bool get isSpeakerEnabled;

  bool get hasRemoteVideo;
}

abstract class VideoCallService {
  Future<CallSession> startCall({
    required String matchId,
    required String receiverId,
  });

  Future<CallSession> acceptCall(String callId);

  Future<void> declineCall(String callId);

  Future<void> endCall(String callId);

  Future<void> expireCall(String callId);

  Stream<CallSession> watchIncoming(String uid);

  Stream<CallSession?> watchCall(String callId);
}

abstract class CallRepository {
  Future<CallSession> createCall({
    required String matchId,
    required String receiverId,
  });

  Future<CallSession> respond({
    required String callId,
    required bool accept,
  });

  Future<void> end(String callId);

  Future<void> expire(String callId);

  Stream<List<CallSession>> watchIncoming(String uid);

  Stream<CallSession?> watchCall(String callId);
}
