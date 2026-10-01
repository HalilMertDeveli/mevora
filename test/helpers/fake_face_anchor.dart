import 'dart:async';

import 'package:mevora/core/di/face_anchor_services_factory.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/domain/repositories/face_anchor_repository.dart';
import 'package:mevora/features/face_anchor/domain/services/live_selfie_capture.dart';

/// A stand-in for the server side of Face Anchor.
///
/// It behaves like the real thing in the one way that matters to the client:
/// the verdict is whatever [nextResult] says, never anything the caller sent.
class FakeFaceAnchorRepository implements FaceAnchorRepository {
  FakeFaceAnchorRepository({
    this.requirements = const FaceAnchorRequirements(
      required: true,
      available: true,
      consentVersion: 1,
    ),
  });

  FaceAnchorRequirements requirements;

  /// What the server answers to the next submit.
  FaceAnchorState nextResult = const FaceAnchorState(
    status: FaceAnchorStatus.verified,
  );

  Failure? startFailure;
  Failure? uploadFailure;
  Failure? submitFailure;

  /// Completes the submit call when set; lets a test hold "verifying" open.
  Completer<void>? submitGate;

  final calls = <String>[];
  final started = <({String photoId, int consentVersion})>[];
  final uploads = <({String path, int bytes, String contentType})>[];
  final submitted = <String>[];

  final _states = StreamController<FaceAnchorState>.broadcast();
  FaceAnchorState _last = FaceAnchorState.none;
  var _attemptSeq = 0;

  /// The server's state document changed.
  void emit(FaceAnchorState state) {
    _last = state;
    _states.add(state);
  }

  @override
  Stream<FaceAnchorState> watchState(String uid) async* {
    yield _last;
    yield* _states.stream;
  }

  @override
  Future<FaceAnchorRequirements> loadRequirements() async => requirements;

  @override
  Future<Result<FaceAnchorAttempt>> startAttempt({
    required String photoId,
    required int consentVersion,
  }) async {
    calls.add('start');
    started.add((photoId: photoId, consentVersion: consentVersion));
    final failure = startFailure;
    if (failure != null) {
      return Err(failure);
    }
    _attemptSeq += 1;
    return Success(
      FaceAnchorAttempt(
        attemptId: 'attempt-$_attemptSeq',
        uploadPath: 'face-anchor/pending/uid/attempt-$_attemptSeq',
        expiresAt: DateTime(2026, 10, 1, 12),
      ),
    );
  }

  @override
  Future<Result<void>> uploadSelfie({
    required FaceAnchorAttempt attempt,
    required List<int> bytes,
    required String contentType,
  }) async {
    calls.add('upload');
    uploads.add((
      path: attempt.uploadPath,
      bytes: bytes.length,
      contentType: contentType,
    ));
    final failure = uploadFailure;
    return failure == null ? const Success(null) : Err(failure);
  }

  @override
  Future<Result<FaceAnchorState>> submitAttempt(String attemptId) async {
    calls.add('submit');
    submitted.add(attemptId);
    await submitGate?.future;
    final failure = submitFailure;
    if (failure != null) {
      return Err(failure);
    }
    final photoId = started.isEmpty ? null : started.last.photoId;
    return Success(
      FaceAnchorState(
        status: nextResult.status,
        reason: nextResult.reason,
        photoId: nextResult.photoId ?? photoId,
        attemptId: attemptId,
      ),
    );
  }

  Future<void> dispose() => _states.close();
}

class FakeLiveSelfieCapture implements LiveSelfieCapture {
  FakeLiveSelfieCapture();

  /// Null means the member closed the camera.
  CapturedSelfie? next = const CapturedSelfie(
    bytes: [0xff, 0xd8, 0xff, 1, 2, 3],
    contentType: 'image/jpeg',
  );
  Failure? failure;
  var captures = 0;

  @override
  Future<Result<CapturedSelfie?>> capture() async {
    captures += 1;
    final failed = failure;
    return failed == null ? Success(next) : Err(failed);
  }
}

FaceAnchorServices createFakeFaceAnchorServices({
  FakeFaceAnchorRepository? repository,
  FakeLiveSelfieCapture? capture,
}) {
  return FaceAnchorServices(
    repository: repository ?? FakeFaceAnchorRepository(),
    capture: capture ?? FakeLiveSelfieCapture(),
  );
}
