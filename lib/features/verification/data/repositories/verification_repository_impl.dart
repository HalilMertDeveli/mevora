import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/verification/data/datasources/firebase_verification_data_source.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification_session.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';

class VerificationRepositoryImpl implements VerificationRepository {
  VerificationRepositoryImpl({required FirebaseVerificationDataSource remote})
    : _remote = remote;

  final FirebaseVerificationDataSource _remote;

  @override
  Stream<IdentityVerification> watchVerification(String uid) {
    return _remote.watchVerification(uid).transform(
      StreamTransformer<IdentityVerification, IdentityVerification>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          // A read failure is not a verdict. Falling back to notStarted keeps
          // the UI usable and, critically, never invents a verified state.
          sink.add(IdentityVerification.notStarted);
        },
      ),
    );
  }

  @override
  Future<Result<IdentityVerificationSession>> startVerificationSession({
    String? language,
  }) async {
    try {
      return Success(await _remote.startVerificationSession(language: language));
    } on Object catch (error) {
      return Err(_mapCallableError(error));
    }
  }

  @override
  Future<void> refreshState() => _remote.refreshState();

  Failure _mapCallableError(Object error) {
    final message = error.toString();
    if (message.contains('verification-not-configured')) {
      return const UnexpectedFailure('verification-not-configured');
    }
    if (message.contains('verification-cooldown')) {
      return const ValidationFailure('verification-cooldown');
    }
    if (message.contains('verification-attempt-limit')) {
      return const ValidationFailure('verification-attempt-limit');
    }
    if (message.contains('already-verified')) {
      return const ValidationFailure('already-verified');
    }
    if (message.contains('verification-in-progress')) {
      return const ValidationFailure('verification-in-progress');
    }
    if (message.contains('verification-unavailable')) {
      return const UnexpectedFailure('verification-unavailable');
    }
    if (message.contains('unauthenticated')) {
      return const AuthFailure('Sign in required.', kind: AuthErrorKind.unknown);
    }
    return FailureMapper.from(error);
  }
}
