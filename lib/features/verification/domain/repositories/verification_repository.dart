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

  /// Asks the backend to create (or resume) a verification session for the
  /// *signed-in* user. There is no uid argument by design — the backend
  /// derives it from the auth context, so a client cannot start a session for
  /// someone else. [language] is a UI hint for the provider's own screens.
  Future<Result<IdentityVerificationSession>> startVerificationSession({
    String? language,
  });

  /// Nudges the backend to re-read and report MEVORA's authoritative state.
  ///
  /// Used when the app returns from the provider flow, where the return
  /// itself proves nothing. Failure is not a verdict — callers keep whatever
  /// the watch stream last gave them.
  Future<void> refreshState();
}
