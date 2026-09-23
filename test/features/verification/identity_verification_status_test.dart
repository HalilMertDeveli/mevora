import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';

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

    test('pending, inProgress and inReview are in flight', () {
      final inFlight = IdentityVerificationStatus.values
          .where((status) => status.isInFlight)
          .toList();
      expect(inFlight, [
        IdentityVerificationStatus.pending,
        IdentityVerificationStatus.inProgress,
        IdentityVerificationStatus.inReview,
      ]);
    });

    test('canStart excludes verified and in-flight states', () {
      expect(IdentityVerificationStatus.notStarted.canStart, isTrue);
      expect(IdentityVerificationStatus.declined.canStart, isTrue);
      expect(IdentityVerificationStatus.expired.canStart, isTrue);
      expect(IdentityVerificationStatus.error.canStart, isTrue);
      expect(IdentityVerificationStatus.pending.canStart, isFalse);
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

    test('no status other than verified shows the badge', () {
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

  group('provider wire names', () {
    test('round-trips every known provider', () {
      for (final provider in IdentityVerificationProvider.values) {
        expect(
          IdentityVerificationProvider.fromWire(provider.wireName),
          provider,
        );
      }
    });

    test('an unknown provider name resolves to null, not a default', () {
      expect(IdentityVerificationProvider.fromWire('onfido'), isNull);
      expect(IdentityVerificationProvider.fromWire(null), isNull);
      expect(IdentityVerificationProvider.fromWire(7), isNull);
    });
  });

  group('sanitized reasons', () {
    test('round-trips every reason', () {
      for (final reason in IdentityVerificationReason.values) {
        expect(IdentityVerificationReason.fromWire(reason.wireName), reason);
      }
    });

    test('an unmapped provider reason is dropped, not surfaced verbatim', () {
      expect(
        IdentityVerificationReason.fromWire('FORGERY_SUSPECTED_MRZ_CHECKSUM'),
        isNull,
      );
      expect(IdentityVerificationReason.fromWire(null), isNull);
    });
  });

  group('retry eligibility', () {
    final now = DateTime.utc(2026, 9, 23, 12);

    test('a verified user may never start again', () {
      const verified = IdentityVerification(
        status: IdentityVerificationStatus.verified,
      );
      final eligibility = verified.retryEligibility(now: now);
      expect(eligibility.allowed, isFalse);
      expect(
        eligibility.blockedBy,
        IdentityVerificationRetryBlock.alreadyVerified,
      );
    });

    test('an in-flight session blocks a second one', () {
      for (final status in [
        IdentityVerificationStatus.pending,
        IdentityVerificationStatus.inProgress,
        IdentityVerificationStatus.inReview,
      ]) {
        final eligibility = IdentityVerification(
          status: status,
        ).retryEligibility(now: now);
        expect(eligibility.allowed, isFalse, reason: 'status=$status');
        expect(eligibility.blockedBy, IdentityVerificationRetryBlock.inFlight);
      }
    });

    test('a first attempt is always allowed', () {
      const fresh = IdentityVerification(
        status: IdentityVerificationStatus.notStarted,
      );
      expect(fresh.retryEligibility(now: now).allowed, isTrue);
    });

    test('the cooldown blocks and reports when it lifts', () {
      final lastAttempt = now.subtract(const Duration(minutes: 3));
      final declined = IdentityVerification(
        status: IdentityVerificationStatus.declined,
        attemptCount: 1,
        lastAttemptAt: lastAttempt,
      );
      final eligibility = declined.retryEligibility(now: now);
      expect(eligibility.allowed, isFalse);
      expect(eligibility.blockedBy, IdentityVerificationRetryBlock.cooldown);
      expect(
        eligibility.retryAvailableAt,
        lastAttempt.add(identityVerificationCooldown),
      );
    });

    test('past the cooldown and under the budget, a retry is allowed', () {
      final declined = IdentityVerification(
        status: IdentityVerificationStatus.declined,
        attemptCount: 2,
        lastAttemptAt: now.subtract(const Duration(minutes: 20)),
      );
      expect(declined.retryEligibility(now: now).allowed, isTrue);
    });

    test('the daily budget blocks even once the cooldown has lifted', () {
      final exhausted = IdentityVerification(
        status: IdentityVerificationStatus.declined,
        attemptCount: identityVerificationMaxAttemptsPerDay,
        lastAttemptAt: now.subtract(const Duration(hours: 2)),
      );
      final eligibility = exhausted.retryEligibility(now: now);
      expect(eligibility.allowed, isFalse);
      expect(eligibility.blockedBy, IdentityVerificationRetryBlock.dailyLimit);
    });

    test('the budget resets a day after the last attempt', () {
      final yesterday = IdentityVerification(
        status: IdentityVerificationStatus.declined,
        attemptCount: identityVerificationMaxAttemptsPerDay,
        lastAttemptAt: now.subtract(const Duration(days: 1, minutes: 1)),
      );
      expect(yesterday.retryEligibility(now: now).allowed, isTrue);
    });

    test('asking about retry never promotes anyone to verified', () {
      for (final status in IdentityVerificationStatus.values) {
        final verification = IdentityVerification(status: status);
        verification.retryEligibility(now: now);
        expect(
          verification.status.grantsVerifiedBadge,
          status == IdentityVerificationStatus.verified,
        );
      }
    });
  });
}
