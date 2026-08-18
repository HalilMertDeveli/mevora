import 'package:mevora/core/errors/result.dart';

enum VideoCallState { ringing, connecting, connected, ended, rejected }

class VideoCall {
  const VideoCall({
    required this.id,
    required this.matchId,
    required this.callerId,
    required this.calleeId,
    required this.state,
  });

  final String id;
  final String matchId;
  final String callerId;
  final String calleeId;
  final VideoCallState state;

  VideoCall copyWith({VideoCallState? state}) {
    return VideoCall(
      id: id,
      matchId: matchId,
      callerId: callerId,
      calleeId: calleeId,
      state: state ?? this.state,
    );
  }
}

/// Video SDK adapter. Swap Agora/WebRTC later without touching UI.
abstract class VideoCallProvider {
  Stream<VideoCall> watch();

  Future<Result<VideoCall>> start({
    required String matchId,
    required String callerId,
    required String calleeId,
  });

  Future<Result<void>> accept(String callId);

  Future<Result<void>> reject(String callId);

  Future<Result<void>> end(String callId);
}
