import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/legacy_verification_bridge.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';

void main() {
  group('provider-neutral identity verification status', () {
    test('exactly one status grants the verified badge', () {
      final granting = IdentityVerificationStatus.values
          .where((status) => status.grantsVerifiedBadge)
          .toList();
      expect(granting, [IdentityVerificationStatus.verified]);
    });

    test('verified, declined and expired are terminal', () {
      final terminal = IdentityVerificationStatus.values
          .where((status) => status.isTerminal)
          .toList();
      expect(terminal, [
        IdentityVerificationStatus.verified,
        IdentityVerificationStatus.declined,
        IdentityVerificationStatus.expired,
      ]);
    });

    test('canStart excludes verified and in-flight states', () {
      expect(IdentityVerificationStatus.notStarted.canStart, isTrue);
      expect(IdentityVerificationStatus.declined.canStart, isTrue);
      expect(IdentityVerificationStatus.expired.canStart, isTrue);
      expect(IdentityVerificationStatus.error.canStart, isTrue);
      expect(IdentityVerificationStatus.inProgress.canStart, isFalse);
      expect(IdentityVerificationStatus.inReview.canStart, isFalse);
      expect(IdentityVerificationStatus.verified.canStart, isFalse);
    });

    test('round-trips every status through the wire format', () {
      for (final status in IdentityVerificationStatus.values) {
        expect(
          identityVerificationStatusFromFirestore(
            identityVerificationStatusToFirestore(status),
          ),
          status,
        );
      }
    });

    test('absent status reads as notStarted', () {
      expect(
        identityVerificationStatusFromFirestore(null),
        IdentityVerificationStatus.notStarted,
      );
      expect(
        identityVerificationStatusFromFirestore(''),
        IdentityVerificationStatus.notStarted,
      );
    });

    test('unrecognised status degrades to error, never to verified', () {
      const hostile = <Object?>[
        'approved',
        'Approved',
        'APPROVED',
        'in_review ',
        true,
        1,
        <String, Object?>{'status': 'verified'},
      ];
      for (final raw in hostile) {
        final status = identityVerificationStatusFromFirestore(raw);
        expect(status, IdentityVerificationStatus.error, reason: 'raw=$raw');
        expect(status.grantsVerifiedBadge, isFalse, reason: 'raw=$raw');
      }
    });

    test('no client-constructible value other than verified shows the badge', () {
      for (final status in IdentityVerificationStatus.values) {
        if (status == IdentityVerificationStatus.verified) {
          continue;
        }
        expect(
          IdentityVerification(status: status).status.grantsVerifiedBadge,
          isFalse,
          reason: 'status=$status',
        );
      }
    });
  });

  group('legacy Sumsub bridge', () {
    test('translates every legacy status', () {
      expect(
        identityStatusFromLegacy(ProfileVerificationStatus.notStarted),
        IdentityVerificationStatus.notStarted,
      );
      expect(
        identityStatusFromLegacy(ProfileVerificationStatus.started),
        IdentityVerificationStatus.inProgress,
      );
      expect(
        identityStatusFromLegacy(ProfileVerificationStatus.pending),
        IdentityVerificationStatus.inReview,
      );
      expect(
        identityStatusFromLegacy(ProfileVerificationStatus.approved),
        IdentityVerificationStatus.verified,
      );
      expect(
        identityStatusFromLegacy(ProfileVerificationStatus.rejected),
        IdentityVerificationStatus.declined,
      );
      expect(
        identityStatusFromLegacy(ProfileVerificationStatus.retryRequired),
        IdentityVerificationStatus.expired,
      );
    });

    test('exactly one legacy status survives as verified', () {
      final granting = ProfileVerificationStatus.values
          .where((legacy) => identityStatusFromLegacy(legacy).grantsVerifiedBadge)
          .toList();
      expect(granting, [ProfileVerificationStatus.approved]);
    });
  });
}
