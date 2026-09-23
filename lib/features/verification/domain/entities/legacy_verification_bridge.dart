import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';

/// Translates the legacy Sumsub-shaped status into the provider-neutral
/// vocabulary, so the neutral domain can read documents the Sumsub pipeline
/// wrote without learning Sumsub's names.
///
/// Production holds no such documents today (0 verification documents, 0
/// verified users — see `docs/DIDIT_MIGRATION_PHASE1.md` STEP 14), so this is
/// a correctness guarantee rather than a live migration path. It keeps the
/// Phase 2 cutover reversible.
IdentityVerificationStatus identityStatusFromLegacy(
  ProfileVerificationStatus legacy,
) {
  return switch (legacy) {
    ProfileVerificationStatus.notStarted => IdentityVerificationStatus.notStarted,
    ProfileVerificationStatus.started => IdentityVerificationStatus.inProgress,
    ProfileVerificationStatus.pending => IdentityVerificationStatus.inReview,
    ProfileVerificationStatus.approved => IdentityVerificationStatus.verified,
    ProfileVerificationStatus.rejected => IdentityVerificationStatus.declined,
    // Sumsub's retry reject means the user may resubmit — the same affordance
    // as an expired session: start again, not a final decline.
    ProfileVerificationStatus.retryRequired => IdentityVerificationStatus.expired,
  };
}
