import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/subscription/domain/entities/subscription_lifecycle.dart';
import 'package:mevora/features/subscription/domain/subscription_entitlement_policy.dart';

void main() {
  final now = DateTime.utc(2026, 9, 22, 12);
  final future = DateTime.utc(2026, 10, 22, 12);
  final past = DateTime.utc(2026, 8, 22, 12);

  Map<String, dynamic> doc({
    String status = 'active',
    String entitlement = 'premium',
    DateTime? expiresAt,
    DateTime? graceUntil,
    bool autoRenewing = true,
  }) {
    return <String, dynamic>{
      'status': status,
      'entitlement': entitlement,
      'expiresAt': expiresAt,
      'graceUntil': graceUntil,
      'autoRenewing': autoRenewing,
      'platform': 'android',
      'productId': 'mevora_premium_monthly',
      'isPremium': true,
    };
  }

  group('canonical lifecycle', () {
    test('active subscription grants premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(expiresAt: future),
        now: now,
      );
      expect(status.isPremium, isTrue);
      expect(status.lifecycle, SubscriptionLifecycle.active);
      expect(status.accessUntil, future);
      expect(status.productId, 'mevora_premium_monthly');
    });

    test('active subscription past its expiry does not grant premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(expiresAt: past),
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('expired subscription does not grant premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'expired', entitlement: 'none', expiresAt: past),
        now: now,
      );
      expect(status.isPremium, isFalse);
      expect(status.lifecycle, SubscriptionLifecycle.expired);
    });

    test('cancelled subscription keeps access until the paid period ends', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'cancelled', expiresAt: future, autoRenewing: false),
        now: now,
      );
      expect(status.isPremium, isTrue);
      expect(status.isCancelledButActive, isTrue);
      expect(status.autoRenewing, isFalse);
      expect(status.accessUntil, future);
    });

    test('cancelled and expired subscription does not grant premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'cancelled', expiresAt: past, autoRenewing: false),
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('cancelled without an expiry fails safe to free', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'cancelled'),
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('grace period keeps access while the window is open', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'grace_period', expiresAt: past, graceUntil: future),
        now: now,
      );
      expect(status.isPremium, isTrue);
      expect(status.isInGracePeriod, isTrue);
      expect(status.accessUntil, future);
    });

    test('grace period that has run out does not grant premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'grace_period', expiresAt: past, graceUntil: past),
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('billing retry without a store grace window is not premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'billing_retry', expiresAt: past),
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('billing retry inside a grace window keeps access', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'billing_retry', expiresAt: past, graceUntil: future),
        now: now,
      );
      expect(status.isPremium, isTrue);
      expect(status.isInGracePeriod, isTrue);
    });

    test('refunded revokes access even inside the paid period', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'refunded', expiresAt: future),
        now: now,
      );
      expect(status.isPremium, isFalse);
      expect(status.lifecycle, SubscriptionLifecycle.refunded);
    });

    test('revoked removes access even inside the paid period', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(status: 'revoked', expiresAt: future),
        now: now,
      );
      expect(status.isPremium, isFalse);
      expect(status.lifecycle, SubscriptionLifecycle.revoked);
    });

    test('entitlement none never grants premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(entitlement: 'none', expiresAt: future),
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('active grant without an expiry stays premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        doc(),
        now: now,
      );
      expect(status.isPremium, isTrue);
      expect(status.accessUntil, isNull);
    });
  });

  group('fail-safe behaviour', () {
    test('missing document is free', () {
      expect(
        SubscriptionEntitlementPolicy.evaluate(null, now: now).isPremium,
        isFalse,
      );
      expect(
        SubscriptionEntitlementPolicy.evaluate(
          <String, dynamic>{},
          now: now,
        ).isPremium,
        isFalse,
      );
    });

    test('unknown status is not trusted as premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{'status': 'something_new', 'entitlement': 'premium'},
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('unknown status with a legacy premium flag stays premium', () {
      // Forward compatibility: a newer backend status we do not know yet must
      // not silently strip a paying user, so the legacy mirror still applies.
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{
          'status': 'something_new',
          'isPremium': true,
          'expiresAt': future,
        },
        now: now,
      );
      expect(status.isPremium, isTrue);
    });

    test('garbage field types do not throw and are not premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{
          'status': 42,
          'entitlement': <String>['premium'],
          'expiresAt': 'tomorrow',
          'autoRenewing': 'yes',
          'isPremium': 'true',
        },
        now: now,
      );
      expect(status.isPremium, isFalse);
      expect(status.autoRenewing, isFalse);
      expect(status.expiresAt, isNull);
    });
  });

  group('pre-P0 documents', () {
    test('legacy premium document without a status is honoured', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{'isPremium': true, 'expiresAt': future},
        now: now,
      );
      expect(status.isPremium, isTrue);
      expect(status.lifecycle, SubscriptionLifecycle.active);
      expect(status.accessUntil, future);
    });

    test('legacy premium document without an expiry is honoured', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{'isPremium': true},
        now: now,
      );
      expect(status.isPremium, isTrue);
    });

    test('legacy premium document past its expiry is not premium', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{'isPremium': true, 'expiresAt': past},
        now: now,
      );
      expect(status.isPremium, isFalse);
    });

    test('legacy non-premium document is free', () {
      final status = SubscriptionEntitlementPolicy.evaluate(
        <String, dynamic>{'isPremium': false},
        now: now,
      );
      expect(status.isPremium, isFalse);
      expect(status.lifecycle, SubscriptionLifecycle.expired);
    });
  });
}
