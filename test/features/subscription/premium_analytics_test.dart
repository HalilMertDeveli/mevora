import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';

class RecordingAnalytics implements AnalyticsProvider {
  final List<String> events = <String>[];
  final List<Map<String, Object>> payloads = <Map<String, Object>>[];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add(name);
    payloads.add(parameters ?? const <String, Object>{});
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

class StubBilling implements PremiumBillingRepository {
  StubBilling({this.plans = const []});

  final List<PremiumPlan> plans;
  PremiumVerificationResult result = const PremiumVerificationResult(
    ok: true,
    isPremium: true,
  );
  Object? throwOnPurchase;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<PremiumPlan>> loadPlans() async => plans;

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async {
    if (throwOnPurchase != null) {
      throw throwOnPurchase!;
    }
    return result;
  }

  @override
  Future<PremiumVerificationResult> restore() async => result;
}

const _plan = PremiumPlan(
  productId: 'mevora_premium_yearly',
  title: 'Premium',
  description: '',
  formattedPrice: 'US\$39.99',
  period: PremiumPlanPeriod.yearly,
);

void main() {
  late RecordingAnalytics analytics;

  setUp(() => analytics = RecordingAnalytics());

  PremiumPurchaseController controllerWith(StubBilling billing) {
    final controller = PremiumPurchaseController(
      billing: billing,
      analytics: analytics,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('loading the paywall reports a view', () async {
    final controller = controllerWith(StubBilling(plans: const [_plan]));
    await controller.loadPlans();
    expect(analytics.events, contains(AnalyticsEvents.premiumPaywallViewed));
  });

  test('a pending payment is not reported as a failed purchase', () async {
    final billing = StubBilling(plans: const [_plan])
      ..result = const PremiumVerificationResult.pending();
    final controller = controllerWith(billing);
    await controller.loadPlans();
    await controller.buySelected();
    expect(
      analytics.events,
      isNot(contains(AnalyticsEvents.premiumPurchaseFailed)),
    );
  });

  test('a successful purchase reports start then success', () async {
    final controller = controllerWith(StubBilling(plans: const [_plan]));
    await controller.loadPlans();
    await controller.buySelected();

    expect(
      analytics.events,
      containsAllInOrder(<String>[
        AnalyticsEvents.premiumPurchaseStarted,
        AnalyticsEvents.premiumPurchaseSuccess,
      ]),
    );
  });

  test('a cancelled purchase is not reported as a failure', () async {
    final billing = StubBilling(plans: const [_plan])
      ..throwOnPurchase = const PremiumBillingException(
        PremiumPurchaseFailure.cancelled,
      );
    final controller = controllerWith(billing);
    await controller.loadPlans();
    await controller.buySelected();

    expect(analytics.events, contains(AnalyticsEvents.premiumPurchaseCancelled));
    expect(
      analytics.events,
      isNot(contains(AnalyticsEvents.premiumPurchaseFailed)),
    );
  });

  test('a refused verification is reported as a failure, not a success', () async {
    final billing = StubBilling(plans: const [_plan])
      ..result = const PremiumVerificationResult(
        ok: false,
        isPremium: false,
        reason: 'owned_by_other',
      );
    final controller = controllerWith(billing);
    await controller.loadPlans();
    await controller.buySelected();

    expect(analytics.events, contains(AnalyticsEvents.premiumPurchaseFailed));
    expect(
      analytics.events,
      isNot(contains(AnalyticsEvents.premiumPurchaseSuccess)),
    );
  });

  test('restore reports its own success, distinct from a purchase', () async {
    final controller = controllerWith(StubBilling(plans: const [_plan]));
    await controller.loadPlans();
    await controller.restore();

    expect(
      analytics.events,
      containsAllInOrder(<String>[
        AnalyticsEvents.premiumRestoreStarted,
        AnalyticsEvents.premiumRestoreSuccess,
      ]),
    );
    expect(
      analytics.events,
      isNot(contains(AnalyticsEvents.premiumPurchaseSuccess)),
    );
  });

  test('no event carries a token, receipt or price', () async {
    final billing = StubBilling(plans: const [_plan])
      ..result = const PremiumVerificationResult(
        ok: false,
        isPremium: false,
        reason: 'owned_by_other',
      );
    final controller = controllerWith(billing);
    await controller.loadPlans();
    await controller.buySelected();
    await controller.restore();

    // A purchase token in an analytics payload is a credential leaving the
    // device, and the backend refusal reason can say something about another
    // user's account. Neither belongs in a funnel event.
    for (final payload in analytics.payloads) {
      expect(payload, isEmpty);
    }
    final flattened = analytics.payloads
        .expand((p) => p.values.map((v) => v.toString()))
        .join(' ');
    expect(flattened, isNot(contains('owned_by_other')));
    expect(flattened, isNot(contains('US\$39.99')));
    expect(flattened, isNot(contains('mevora_premium_yearly')));
  });

  test('analytics failures never break a purchase', () async {
    final controller = PremiumPurchaseController(
      billing: StubBilling(plans: const [_plan]),
      analytics: _ThrowingAnalytics(),
    );
    addTearDown(controller.dispose);

    await controller.loadPlans();
    await controller.buySelected();

    expect(controller.stage, PremiumPurchaseStage.purchased);
  });

  test('a controller without analytics still works', () async {
    final controller = PremiumPurchaseController(
      billing: StubBilling(plans: const [_plan]),
    );
    addTearDown(controller.dispose);

    await controller.loadPlans();
    await controller.buySelected();

    expect(controller.stage, PremiumPurchaseStage.purchased);
  });
}

class _ThrowingAnalytics implements AnalyticsProvider {
  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    throw StateError('analytics is down');
  }

  @override
  Future<void> setUserId(String? userId) async {}
}
