import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification_session.dart';

/// The application's only route to identity verification.
///
/// Provider-neutral by contract: no method name, argument or return type
/// mentions Sumsub or Didit. Which provider is in use, how a session is
/// created and what its statuses are called all live behind the data source.
abstract class VerificationRepository {
  /// The server-authoritative verification state for [uid]. This stream is
  /// the only source the UI may trust; nothing the client computes adds to it.
  Stream<IdentityVerification> watchVerification(String uid);

  /// Asks the backend to create a verification session for the *signed-in*
  /// user. There is no uid argument by design — the backend derives it from
  /// the auth context, so a client cannot start a session for someone else.
  Future<Result<IdentityVerificationSession>> startVerificationSession();
}
