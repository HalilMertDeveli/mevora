import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/face_anchor/data/datasources/firebase_face_anchor_data_source.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/domain/face_anchor_messages.dart';
import 'package:mevora/features/face_anchor/domain/repositories/face_anchor_repository.dart';

class FaceAnchorRepositoryImpl implements FaceAnchorRepository {
  FaceAnchorRepositoryImpl({required FirebaseFaceAnchorDataSource remote})
    : _remote = remote;

  final FirebaseFaceAnchorDataSource _remote;

  @override
  Stream<FaceAnchorState> watchState(String uid) => _remote.watchState(uid);

  @override
  Future<FaceAnchorRequirements> loadRequirements() async {
    try {
      return await _remote.loadRequirements();
    } on Object {
      return FaceAnchorRequirements.unknown;
    }
  }

  @override
  Future<Result<FaceAnchorAttempt>> startAttempt({
    required String photoId,
    required int consentVersion,
  }) async {
    try {
      return Success(
        await _remote.startAttempt(
          photoId: photoId,
          consentVersion: consentVersion,
        ),
      );
    } on Object catch (error) {
      return Err(mapCallableError(error));
    }
  }

  @override
  Future<Result<void>> uploadSelfie({
    required FaceAnchorAttempt attempt,
    required List<int> bytes,
    required String contentType,
  }) async {
    try {
      await _remote.uploadSelfie(
        path: attempt.uploadPath,
        bytes: bytes,
        contentType: contentType,
      );
      return const Success(null);
    } on Object {
      // Storage codes and paths stay out of the message on purpose.
      return const Err(NetworkFailure(FaceAnchorMessages.uploadFailed));
    }
  }

  @override
  Future<Result<FaceAnchorState>> submitAttempt(String attemptId) async {
    try {
      return Success(await _remote.submitAttempt(attemptId));
    } on Object catch (error) {
      return Err(mapCallableError(error));
    }
  }

  /// Maps the server's refusal words onto [FaceAnchorMessages]. Anything not
  /// recognised becomes the generic message — never the raw error text.
  static Failure mapCallableError(Object error) {
    final message = error.toString();
    const known = <String, String>{
      'face-anchor-unavailable': FaceAnchorMessages.unavailable,
      'consent-required': FaceAnchorMessages.consentRequired,
      'photo-not-approved': FaceAnchorMessages.photoNotApproved,
      'photo-not-found': FaceAnchorMessages.photoNotFound,
      'already-verified': FaceAnchorMessages.alreadyVerified,
      'verification-in-progress': FaceAnchorMessages.inProgress,
      'face-anchor-cooldown': FaceAnchorMessages.cooldown,
      'face-anchor-attempt-limit': FaceAnchorMessages.attemptLimit,
      'too-many-requests': FaceAnchorMessages.tooManyRequests,
      'selfie-missing': FaceAnchorMessages.uploadFailed,
      'attempt-not-found': FaceAnchorMessages.attemptExpired,
      'account-suspended': FaceAnchorMessages.accountNotAllowed,
      'account-missing': FaceAnchorMessages.accountNotAllowed,
    };
    for (final entry in known.entries) {
      if (message.contains(entry.key)) {
        return ValidationFailure(entry.value);
      }
    }
    if (error is TimeoutException ||
        message.contains('unavailable') ||
        message.contains('deadline-exceeded') ||
        message.contains('network')) {
      return const NetworkFailure(FaceAnchorMessages.network);
    }
    return const UnexpectedFailure(FaceAnchorMessages.generic);
  }
}
