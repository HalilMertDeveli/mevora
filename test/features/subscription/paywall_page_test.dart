import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/features/subscription/presentation/controllers/subscription_controller.dart';
import 'package:mevora/features/subscription/presentation/pages/paywall_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

class _StaticSubscriptionRepository implements SubscriptionRepository {
  _StaticSubscriptionRepository(this.status);

  final PremiumStatus status;

  @override
  Stream<PremiumStatus> watch() => Stream.value(status);
}

class _StubBilling implements PremiumBillingRepository {
  _StubBilling({this.plans = const []});

  final List<PremiumPlan> plans;
  int purchaseCalls = 0;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<PremiumPlan>> loadPlans() async => plans;

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async {
    purchaseCalls += 1;
    return const PremiumVerificationResult(ok: true, isPremium: true);
  }

  @override
  Future<PremiumVerificationResult> restore() async =>
      const PremiumVerificationResult(ok: true, isPremium: true);
}

Future<void> _pump(
  WidgetTester tester, {
  required PremiumStatus status,
  required PremiumBillingRepository billing,
}) async {
  final repository = _StaticSubscriptionRepository(status);
  final controller = SubscriptionController(repository: repository)..start();
  addTearDown(controller.dispose);
  final purchase = PremiumPurchaseController(billing: billing);
  addTearDown(purchase.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SubscriptionScope(
        controller: controller,
        repository: repository,
        billing: billing,
        child: PaywallPage(controller: purchase),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const plan = PremiumPlan(
    productId: 'premium_yearly',
    title: 'Premium (Yearly)',
    description: 'Everything in Premium',
    // Deliberately a currency the app never formats itself.
    formattedPrice: 'US\$39.99',
    period: PremiumPlanPeriod.yearly,
  );

  testWidgets('a free user sees the store price exactly as the store gave it', (
    tester,
  ) async {
    await _pump(
      tester,
      status: PremiumStatus.free,
      billing: _StubBilling(plans: const [plan]),
    );

    expect(find.text('US\$39.99'), findsOneWidget);
    expect(find.text('Premium (Yearly)'), findsOneWidget);
  });

  testWidgets('an already-Premium user is not sold anything', (tester) async {
    final billing = _StubBilling(plans: const [plan]);
    await _pump(
      tester,
      status: const PremiumStatus(isPremium: true),
      billing: billing,
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.premiumAlreadyActive), findsOneWidget);
    // No plan, no price, no subscribe button.
    expect(find.text('US\$39.99'), findsNothing);
    expect(find.text(l10n.premiumSubscribeCta), findsNothing);
    expect(billing.purchaseCalls, 0);
  });

  testWidgets('no plans shows unavailable rather than an empty buy screen', (
    tester,
  ) async {
    await _pump(
      tester,
      status: PremiumStatus.free,
      billing: _StubBilling(),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.premiumUnavailableTitle), findsOneWidget);
    expect(find.text(l10n.premiumSubscribeCta), findsNothing);
  });

  testWidgets('entitlement, not purchase state, decides what is shown', (
    tester,
  ) async {
    // The purchase controller is left at idle: it has never seen a purchase.
    // The scope alone says Premium, and that is enough.
    await _pump(
      tester,
      status: const PremiumStatus(isPremium: true),
      billing: _StubBilling(plans: const [plan]),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.premiumAlreadyActive), findsOneWidget);
  });
}
