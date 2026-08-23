import 'dart:async';

import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/verification/data/datasources/firebase_verification_data_source.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';

class VerificationRepositoryImpl implements VerificationRepository {
  VerificationRepositoryImpl({required FirebaseVerificationDataSource remote})
    : _remote = remote;

  final FirebaseVerificationDataSource _remote;

  @override
  Stream<ProfileVerification> watchVerification(String uid) {
    return _remote.watchVerification(uid).transform(
      StreamTransformer<ProfileVerification, ProfileVerification>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          sink.add(ProfileVerification.notStarted);
        },
      ),
    );
  }

  @override
  Future<Result<String>> createAccessToken() async {
    try {
      final token = await _remote.createAccessToken();
      return Success(token);
    } on Object catch (error) {
      return Err(_mapCallableError(error));
    }
  }

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
    if (message.contains('unauthenticated')) {
      return const AuthFailure('Sign in required.', kind: AuthErrorKind.unknown);
    }
    return FailureMapper.from(error);
  }
}
