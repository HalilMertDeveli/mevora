import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/video/domain/video_call_provider.dart';

class StartVideoCall {
  const StartVideoCall(this._provider, {required this.featureFlags});

  final VideoCallProvider _provider;
  final FeatureFlags featureFlags;

  Future<Result<VideoCall>> call({
    required String matchId,
    required String callerId,
    required String calleeId,
  }) async {
    if (!featureFlags.videoCallsEnabled) {
      return const Err<VideoCall>(
        PermissionFailure('Video calls are not available'),
      );
    }
    return _provider.start(
      matchId: matchId,
      callerId: callerId,
      calleeId: calleeId,
    );
  }
}

class AcceptVideoCall {
  const AcceptVideoCall(this._provider, {required this.featureFlags});

  final VideoCallProvider _provider;
  final FeatureFlags featureFlags;

  Future<Result<void>> call(String callId) async {
    if (!featureFlags.videoCallsEnabled) {
      return const Err<void>(
        PermissionFailure('Video calls are not available'),
      );
    }
    return _provider.accept(callId);
  }
}

class RejectVideoCall {
  const RejectVideoCall(this._provider);

  final VideoCallProvider _provider;

  Future<Result<void>> call(String callId) => _provider.reject(callId);
}

class EndVideoCall {
  const EndVideoCall(this._provider);

  final VideoCallProvider _provider;

  Future<Result<void>> call(String callId) => _provider.end(callId);
}
