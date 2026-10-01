import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';

/// The app's side of Face Anchor verification.
///
/// Three steps the server keeps separate — open an attempt, send the selfie,
/// ask for the verdict — and a stream of the attempt's state. Nothing here
/// can mark a photo verified: every method either asks the server to do
/// something or reports what the server recorded.
abstract class FaceAnchorRepository {
  /// The member's current attempt, live. Emits [FaceAnchorState.none] when
  /// there has never been one.
  Stream<FaceAnchorState> watchState(String uid);

  /// Never throws: an unreachable server reads as
  /// [FaceAnchorRequirements.unknown].
  Future<FaceAnchorRequirements> loadRequirements();

  Future<Result<FaceAnchorAttempt>> startAttempt({
    required String photoId,
    required int consentVersion,
  });

  /// Sends the selfie to the one place the server will read it from. The
  /// object is write-once and unreadable, so no URL comes back.
  Future<Result<void>> uploadSelfie({
    required FaceAnchorAttempt attempt,
    required List<int> bytes,
    required String contentType,
  });

  /// Asks for the verdict. Safe to repeat: the server runs an attempt once
  /// and answers a repeat with the recorded result.
  Future<Result<FaceAnchorState>> submitAttempt(String attemptId);
}
