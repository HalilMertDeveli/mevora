import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/video/domain/video_call_provider.dart';

class FakeVideoCallProvider implements VideoCallProvider {
  final _controller = StreamController<VideoCall>.broadcast();
  final Map<String, VideoCall> _calls = {};

  @override
  Stream<VideoCall> watch() => _controller.stream;

  @override
  Future<Result<VideoCall>> start({
    required String matchId,
    required String callerId,
    required String calleeId,
  }) async {
    final call = VideoCall(
      id: 'call-$matchId',
      matchId: matchId,
      callerId: callerId,
      calleeId: calleeId,
      state: VideoCallState.ringing,
    );
    _calls[call.id] = call;
    _controller.add(call);
    return Success(call);
  }

  @override
  Future<Result<void>> accept(String callId) =>
      _setState(callId, VideoCallState.connected);

  @override
  Future<Result<void>> reject(String callId) =>
      _setState(callId, VideoCallState.rejected);

  @override
  Future<Result<void>> end(String callId) =>
      _setState(callId, VideoCallState.ended);

  Future<Result<void>> _setState(String callId, VideoCallState state) async {
    final existing = _calls[callId];
    if (existing == null) {
      return const Err(NotFoundFailure('Call not found'));
    }
    final updated = existing.copyWith(state: state);
    _calls[callId] = updated;
    _controller.add(updated);
    return const Success(null);
  }

  void dispose() {
    unawaited(_controller.close());
  }
}
