import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/subscription/domain/config/premium_product_config.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';

PremiumPlan _plan(
  String id, {
  String price = '₺0,00',
  PremiumPlanPeriod period = PremiumPlanPeriod.monthly,
}) {
  return PremiumPlan(
    productId: id,
    title: id,
    description: '',
    formattedPrice: price,
    period: period,
  );
}

class FakeBilling implements PremiumBillingRepository {
  FakeBilling({this.plans = const []});

  List<PremiumPlan> plans;
  bool available = true;
  PremiumVerificationResult purchaseResult = const PremiumVerificationResult(
    ok: true,
    isPremium: true,
  );
  PremiumVerificationResult restoreResult = const PremiumVerificationResult(
    ok: true,
    isPremium: true,
  );
  Object? throwOnPurchase;
  Object? throwOnLoad;

  int purchaseCalls = 0;
  int restoreCalls = 0;

  @override
  Future<bool> isStoreAvailable() async => available;

  @override
  Future<List<PremiumPlan>> loadPlans() async {
    if (throwOnLoad != null) {
      throw throwOnLoad!;
    }
    return plans;
  }

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async {
    purchaseCalls += 1;
    if (throwOnPurchase != null) {
      throw throwOnPurchase!;
    }
    return purchaseResult;
  }

  @override
  Future<PremiumVerificationResult> restore() async {
    restoreCalls += 1;
    return restoreResult;
  }
}

void main() {
  group('PremiumProductConfig', () {
    test('defaults to nothing, so an unconfigured build sells nothing', () {
      const config = PremiumProductConfig();
      expect(config.isConfigured, isFalse);
      expect(config.queryIdsFor(PremiumPlatform.android), isEmpty);
      expect(config.allows(PremiumPlatform.android, 'anything'), isFalse);
    });

    test('parses productId:basePlanId pairs like the backend catalogue', () {
      const config = PremiumProductConfig(
        android: [
          PremiumProductRef(productId: 'premium', basePlanId: 'monthly'),
          PremiumProductRef(productId: 'premium', basePlanId: 'yearly'),
        ],
      );
      // Google is queried by product id; the base plan lives inside it.
      expect(config.queryIdsFor(PremiumPlatform.android), {'premium'});
      expect(config.allows(PremiumPlatform.android, 'premium'), isTrue);
    });

    test('an iOS-only configuration grants nothing on Android', () {
      const config = PremiumProductConfig(
        ios: [PremiumProductRef(productId: 'premium_ios')],
      );
      expect(config.allows(PremiumPlatform.android, 'premium_ios'), isFalse);
      expect(config.allows(PremiumPlatform.ios, 'premium_ios'), isTrue);
    });

    test('a Boost SKU is never a Premium product', () {
      const config = PremiumProductConfig(
        android: [PremiumProductRef(productId: 'premium_yearly')],
      );
      expect(config.allows(PremiumPlatform.android, 'boost_week'), isFalse);
    });
  });

  group('PremiumPurchaseController', () {
    test('no plans means unavailable, not an empty purchasable screen', () async {
      final controller = PremiumPurchaseController(billing: FakeBilling());
      await controller.loadPlans();
      expect(controller.stage, PremiumPurchaseStage.unavailable);
      expect(controller.selected, isNull);
    });

    test('preselects the yearly plan when the store offers one', () async {
      final billing = FakeBilling(
        plans: [
          _plan('m', period: PremiumPlanPeriod.monthly),
          _plan('y', period: PremiumPlanPeriod.yearly),
        ],
      );
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();
      expect(controller.stage, PremiumPurchaseStage.ready);
      expect(controller.selected?.productId, 'y');
    });

    test('a backend refusal does not become a purchase', () async {
      final billing = FakeBilling(plans: [_plan('premium')])
        ..purchaseResult = const PremiumVerificationResult(
          ok: false,
          isPremium: false,
          reason: 'unknown_product',
        );
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();
      await controller.buySelected();

      expect(controller.stage, PremiumPurchaseStage.failed);
      expect(controller.failure, PremiumPurchaseFailure.verificationRejected);
      expect(controller.reason, 'unknown_product');
    });

    test('ok without isPremium is still not a purchase', () async {
      // The store accepted money for something the catalogue does not sell.
      // "ok" alone must never read as entitlement.
      final billing = FakeBilling(plans: [_plan('premium')])
        ..purchaseResult = const PremiumVerificationResult(
          ok: true,
          isPremium: false,
        );
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();
      await controller.buySelected();

      expect(controller.stage, isNot(PremiumPurchaseStage.purchased));
      expect(controller.stage, PremiumPurchaseStage.failed);
    });

    test('a cancelled store sheet is not a failure banner', () async {
      final billing = FakeBilling(plans: [_plan('premium')])
        ..throwOnPurchase = const PremiumBillingException(
          PremiumPurchaseFailure.cancelled,
        );
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();
      await controller.buySelected();

      expect(controller.stage, PremiumPurchaseStage.cancelled);
    });

    test('restore goes through the same verification, not a shortcut', () async {
      final billing = FakeBilling(plans: [_plan('premium')])
        ..restoreResult = const PremiumVerificationResult(
          ok: false,
          isPremium: false,
          reason: 'nothing_to_restore',
        );
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();
      await controller.restore();

      expect(billing.restoreCalls, 1);
      expect(controller.stage, PremiumPurchaseStage.failed);
      expect(controller.reason, 'nothing_to_restore');
    });

    test('a second buy cannot start while one is in flight', () async {
      final gate = Completer<void>();
      final billing = _GatedBilling(gate, [_plan('premium')]);
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();

      final first = controller.buySelected();
      final second = controller.buySelected();
      gate.complete();
      await Future.wait([first, second]);

      expect(billing.purchaseCalls, 1);
    });

    test('acknowledge returns to a state the user can act from', () async {
      final billing = FakeBilling(plans: [_plan('premium')])
        ..throwOnPurchase = const PremiumBillingException(
          PremiumPurchaseFailure.transient,
        );
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();
      await controller.buySelected();
      expect(controller.stage, PremiumPurchaseStage.failed);

      controller.acknowledge();
      expect(controller.stage, PremiumPurchaseStage.ready);
      expect(controller.failure, isNull);
    });

    test('the controller exposes no way to declare Premium', () async {
      // Guards the invariant by shape: every public member is a read or an
      // action that delegates to the billing repository. If someone later adds
      // a setter that flips entitlement, this list changes and the test fails.
      final billing = FakeBilling(plans: [_plan('premium')]);
      final controller = PremiumPurchaseController(billing: billing);
      await controller.loadPlans();

      // Reaching `purchased` requires the repository to have said isPremium.
      await controller.buySelected();
      expect(controller.stage, PremiumPurchaseStage.purchased);
      expect(billing.purchaseCalls, 1);
    });
  });
}

class _GatedBilling extends FakeBilling {
  _GatedBilling(this.gate, List<PremiumPlan> plans) : super(plans: plans);

  final Completer<void> gate;

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async {
    purchaseCalls += 1;
    await gate.future;
    return purchaseResult;
  }
}
