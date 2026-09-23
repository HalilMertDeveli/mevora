import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/legacy_verification_bridge.dart';

/// Backward compatibility for verification documents written before the
/// provider-neutral migration. Production holds none
/// (`docs/DIDIT_MIGRATION_PHASE1.md` STEP 14), so these assertions exist to
/// prove that if one did exist it would render correctly rather than crash —
/// and, in particular, that it could not grant a badge it never earned.
void main() {
  group('legacy verification document', () {
    test('translates every legacy wire status', () {
      expect(
        identityStatusFromLegacyWire('not_started'),
        IdentityVerificationStatus.notStarted,
      );
      expect(
        identityStatusFromLegacyWire('started'),
        IdentityVerificationStatus.inProgress,
      );
      expect(
        identityStatusFromLegacyWire('pending'),
        IdentityVerificationStatus.inReview,
      );
      expect(
        identityStatusFromLegacyWire('approved'),
        IdentityVerificationStatus.verified,
      );
      expect(
        identityStatusFromLegacyWire('rejected'),
        IdentityVerificationStatus.declined,
      );
      expect(
        identityStatusFromLegacyWire('retry_required'),
        IdentityVerificationStatus.expired,
      );
    });

    test('an absent legacy status reads as notStarted, not as an error', () {
      expect(
        identityStatusFromLegacyWire(null),
        IdentityVerificationStatus.notStarted,
      );
      expect(
        identityStatusFromLegacyWire(''),
        IdentityVerificationStatus.notStarted,
      );
    });

    test('exactly one legacy status survives as verified', () {
      const legacyVocabulary = [
        'not_started',
        'started',
        'pending',
        'approved',
        'rejected',
        'retry_required',
      ];
      final granting = legacyVocabulary
          .where((raw) => identityStatusFromLegacyWire(raw).grantsVerifiedBadge)
          .toList();
      expect(granting, ['approved']);
    });

    test('a raw provider verdict is not a legacy status', () {
      for (final raw in <Object?>['GREEN', 'Approved', 'verified', 1, true]) {
        final status = identityStatusFromLegacyWire(raw);
        expect(status, IdentityVerificationStatus.error, reason: 'raw=$raw');
        expect(status.grantsVerifiedBadge, isFalse, reason: 'raw=$raw');
      }
    });

    test('legacy field names stay confined to the legacy reader', () {
      expect(LegacyVerificationFields.docId, 'sumsub');
      expect(LegacyVerificationFields.status, 'verificationStatus');
      expect(LegacyVerificationFields.providerSessionId, 'sumsubApplicantId');
    });
  });
}
