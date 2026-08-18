import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/video/domain/video_call_provider.dart';

class DisabledVideoCallProvider implements VideoCallProvider {
  const DisabledVideoCallProvider();

  @override
  Stream<VideoCall> watch() => const Stream.empty();

  @override
  Future<Result<VideoCall>> start({
    required String matchId,
    required String callerId,
    required String calleeId,
  }) async {
    return const Err<VideoCall>(
      PermissionFailure('Video calls are not available'),
    );
  }

  @override
  Future<Result<void>> accept(String callId) async {
    return const Err<void>(
      PermissionFailure('Video calls are not available'),
    );
  }

  @override
  Future<Result<void>> reject(String callId) async {
    return const Err<void>(
      PermissionFailure('Video calls are not available'),
    );
  }

  @override
  Future<Result<void>> end(String callId) async {
    return const Err<void>(
      PermissionFailure('Video calls are not available'),
    );
  }
}
