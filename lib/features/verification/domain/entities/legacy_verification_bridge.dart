import 'package:mevora/features/verification/domain/entities/identity_verification.dart';

/// Reads a pre-neutral (Sumsub-shaped) verification document.
///
/// Before the provider-neutral migration MEVORA stored its state at
/// `users/{uid}/verification/sumsub` with Sumsub's review vocabulary
/// (`started`, `pending`, `approved`, `rejected`, `retry_required`) and a
/// `sumsubApplicantId`. This translates that layout into the neutral one so a
/// legacy document renders instead of crashing or reading as `error`.
///
/// Production holds no such documents (0 verification documents, 0 verified
/// users — `docs/DIDIT_MIGRATION_PHASE1.md` STEP 14), so this is a
/// belt-and-braces reader, not a live migration path. It is deliberately
/// small and has no write side: nothing writes the legacy layout any more.
///
/// The legacy vocabulary is matched as raw wire strings rather than through a
/// Sumsub-named enum, so no provider name survives in a domain contract.
IdentityVerificationStatus identityStatusFromLegacyWire(Object? raw) {
  if (raw == null || raw == '') {
    return IdentityVerificationStatus.notStarted;
  }
  return switch (raw) {
    'not_started' => IdentityVerificationStatus.notStarted,
    'started' => IdentityVerificationStatus.inProgress,
    'pending' => IdentityVerificationStatus.inReview,
    'approved' => IdentityVerificationStatus.verified,
    'rejected' => IdentityVerificationStatus.declined,
    // The legacy "retry" reject meant the user could resubmit — the same
    // affordance as an expired session: start again, not a final decline.
    'retry_required' => IdentityVerificationStatus.expired,
    _ => IdentityVerificationStatus.error,
  };
}

/// Field names used by the pre-neutral document, kept in one place so the
/// legacy reader is the only code that knows them.
class LegacyVerificationFields {
  const LegacyVerificationFields._();

  static const docId = 'sumsub';
  static const status = 'verificationStatus';
  static const providerSessionId = 'sumsubApplicantId';
  static const updatedAt = 'verificationUpdatedAt';
  static const verifiedAt = 'verifiedAt';
  static const attemptCount = 'verificationAttemptCount';
  static const lastAttemptAt = 'lastVerificationAttemptAt';
}
