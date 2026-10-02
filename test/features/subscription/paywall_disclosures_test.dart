import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/features/subscription/presentation/controllers/subscription_controller.dart';
import 'package:mevora/features/subscription/presentation/pages/paywall_page.dart';
import 'package:mevora/features/subscription/presentation/widgets/manage_subscription.dart';
import 'package:mevora/features/subscription/presentation/widgets/purchase_legal_links.dart';
import 'package:mevora/l10n/app_localizations.dart';

class _StaticSubscriptionRepository implements SubscriptionRepository {
  _StaticSubscriptionRepository(this.status);

  final PremiumStatus status;

  @override
  Stream<PremiumStatus> watch() => Stream.value(status);
}

class _StubBilling implements PremiumBillingRepository {
  _StubBilling(this.plans);

  final List<PremiumPlan> plans;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<PremiumPlan>> loadPlans() async => plans;

  @override
  Future<PremiumVerificationResult> purchase(PremiumPlan plan) async =>
      const PremiumVerificationResult(ok: true, isPremium: true);

  @override
  Future<PremiumVerificationResult> restore() async =>
      const PremiumVerificationResult(ok: true, isPremium: true);
}

const _monthly = PremiumPlan(
  productId: 'mevora_premium',
  basePlanId: 'monthly',
  title: 'Premium Monthly',
  description: 'Everything in Premium',
  // A price the app could not have produced itself.
  formattedPrice: '₺149,99',
  period: PremiumPlanPeriod.monthly,
);

const _yearly = PremiumPlan(
  productId: 'mevora_premium',
  basePlanId: 'yearly',
  title: 'Premium Yearly',
  description: 'Everything in Premium',
  formattedPrice: '₺1.299,99',
  period: PremiumPlanPeriod.yearly,
);

const _premiumOnPlay = PremiumStatus(
  isPremium: true,
  platform: 'android',
  productId: 'mevora_premium',
);

/// The paywall inside a real router, so the legal links go where the app
/// sends them. [launched] collects every store link the page tries to open.
Future<void> _pump(
  WidgetTester tester, {
  required PremiumStatus status,
  List<PremiumPlan> plans = const [_monthly, _yearly],
  Locale locale = const Locale('en'),
  Size size = const Size(800, 1800),
  double textScale = 1.0,
  SubscriptionStoreLauncher? launcher,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _StaticSubscriptionRepository(status);
  final controller = SubscriptionController(repository: repository)..start();
  addTearDown(controller.dispose);
  final billing = _StubBilling(plans);
  final purchase = PremiumPurchaseController(billing: billing);
  addTearDown(purchase.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.premium,
    routes: [
      GoRoute(
        path: AppRoutes.premium,
        builder: (context, state) => launcher == null
            ? PaywallPage(controller: purchase)
            : PaywallPage(controller: purchase, storeLauncher: launcher),
      ),
      GoRoute(
        path: AppRoutes.legalTerms,
        builder: (context, state) =>
            Scaffold(appBar: AppBar(), body: const Text('terms page')),
      ),
      GoRoute(
        path: AppRoutes.legalPrivacy,
        builder: (context, state) =>
            Scaffold(appBar: AppBar(), body: const Text('privacy page')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: SubscriptionScope(
          controller: controller,
          repository: repository,
          billing: billing,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _disclosure(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const Key('paywallRenewalDisclosure')))
      .data!;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('each plan shows the store price and how often it is billed', (
    tester,
  ) async {
    await _pump(tester, status: PremiumStatus.free);

    // The store's strings, untouched.
    expect(find.text('₺149,99'), findsOneWidget);
    expect(find.text('₺1.299,99'), findsOneWidget);
    expect(find.textContaining(en.premiumPlanBilledMonthly), findsOneWidget);
    expect(find.textContaining(en.premiumPlanBilledYearly), findsOneWidget);
  });

  testWidgets('the renewal disclosure names the selected price and period, '
      'and where to cancel', (tester) async {
    await _pump(tester, status: PremiumStatus.free);

    // Yearly is preselected.
    expect(find.text('₺1.299,99 / year'), findsOneWidget);
    expect(_disclosure(tester), contains(en.premiumRenewalYearly('₺1.299,99')));
    expect(_disclosure(tester), contains('renews automatically'));
    expect(_disclosure(tester), contains('until you cancel'));
    expect(_disclosure(tester), contains('Google Play > Subscriptions'));

    await tester.tap(find.text('Premium Monthly'));
    await tester.pumpAndSettle();

    expect(find.text('₺149,99 / month'), findsOneWidget);
    expect(find.text('₺1.299,99 / year'), findsNothing);
    expect(_disclosure(tester), contains(en.premiumRenewalMonthly('₺149,99')));
  });

  testWidgets('a plan with no readable period promises none', (tester) async {
    const opaque = PremiumPlan(
      productId: 'mevora_premium',
      title: 'Mevora Premium',
      description: '',
      formattedPrice: 'US\$9.99',
    );
    await _pump(tester, status: PremiumStatus.free, plans: const [opaque]);

    expect(find.textContaining(en.premiumPlanBilledMonthly), findsNothing);
    expect(find.textContaining(en.premiumPlanBilledYearly), findsNothing);
    expect(find.textContaining('/ month'), findsNothing);
    expect(find.textContaining('/ year'), findsNothing);
    expect(_disclosure(tester), contains(en.premiumRenewalGeneric('US\$9.99')));
  });

  test('the billing period is read from Turkish store titles too', () {
    PremiumPlan titled(String title, {String? basePlanId}) => PremiumPlan(
      productId: 'mevora_premium',
      basePlanId: basePlanId,
      title: title,
      description: '',
      formattedPrice: '₺1',
    );

    expect(billingPeriodOf(titled('Premium Aylık')), PremiumPlanPeriod.monthly);
    expect(
      billingPeriodOf(titled('Premium · 1 Ay')),
      PremiumPlanPeriod.monthly,
    );
    expect(billingPeriodOf(titled('Premium Yıllık')), PremiumPlanPeriod.yearly);
    expect(
      billingPeriodOf(titled('Premium · 1 Yıl')),
      PremiumPlanPeriod.yearly,
    );
    expect(
      billingPeriodOf(titled('Mevora Premium', basePlanId: 'yearly')),
      PremiumPlanPeriod.yearly,
    );
    expect(
      billingPeriodOf(titled('Mevora Premium')),
      PremiumPlanPeriod.unknown,
    );
    // What the store repository already decided is never second-guessed.
    expect(billingPeriodOf(_monthly), PremiumPlanPeriod.monthly);
  });

  testWidgets('restore stays on the paywall', (tester) async {
    await _pump(tester, status: PremiumStatus.free);

    expect(find.text(en.premiumRestoreCta), findsOneWidget);
    expect(find.text(en.premiumSubscribeCta), findsOneWidget);
  });

  testWidgets('Terms and Privacy are links that open the in-app legal pages', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, status: PremiumStatus.free);

    expect(
      tester.getSemantics(find.byKey(PurchaseLegalLinks.termsKey)),
      isSemantics(label: en.termsOfService, isLink: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byKey(PurchaseLegalLinks.privacyKey)),
      isSemantics(label: en.privacyPolicy, isLink: true, hasTapAction: true),
    );

    await tester.tap(find.byKey(PurchaseLegalLinks.termsKey));
    await tester.pumpAndSettle();
    expect(find.text('terms page'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PurchaseLegalLinks.privacyKey));
    await tester.pumpAndSettle();
    expect(find.text('privacy page'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a free member is not offered subscription management', (
    tester,
  ) async {
    await _pump(tester, status: PremiumStatus.free);

    expect(find.text(en.premiumManageSubscription), findsNothing);
  });

  testWidgets('a Premium member can open their subscription in Google Play', (
    tester,
  ) async {
    final launched = <Uri>[];
    await _pump(
      tester,
      status: _premiumOnPlay,
      launcher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    expect(find.text(en.premiumSubscribeCta), findsNothing);
    await tester.tap(find.text(en.premiumManageSubscription));
    await tester.pumpAndSettle();

    expect(launched, hasLength(1));
    expect(
      launched.single.toString(),
      'https://play.google.com/store/account/subscriptions'
      '?package=com.mevora.app&sku=mevora_premium',
    );
    expect(find.byType(SnackBar), findsNothing);
    // The legal pages stay reachable after the sale, too.
    expect(find.byKey(PurchaseLegalLinks.termsKey), findsOneWidget);
  });

  testWidgets('a link that cannot be opened says where to go instead', (
    tester,
  ) async {
    await _pump(tester, status: _premiumOnPlay, launcher: (uri) async => false);
    await tester.tap(find.text(en.premiumManageSubscription));
    await tester.pumpAndSettle();

    expect(
      find.text(en.premiumManageSubscriptionFailed('Google Play')),
      findsOneWidget,
    );
  });

  testWidgets('a launcher that throws is reported, not crashed on', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _premiumOnPlay,
      launcher: (uri) async => throw StateError('no handler'),
    );
    await tester.tap(find.text(en.premiumManageSubscription));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text(en.premiumManageSubscriptionFailed('Google Play')),
      findsOneWidget,
    );
  });

  test('the manage link targets the store that holds the subscription', () {
    expect(
      manageSubscriptionUri(
        store: SubscriptionStore.googlePlay,
        packageName: 'com.mevora.app.staging',
      ).toString(),
      'https://play.google.com/store/account/subscriptions'
      '?package=com.mevora.app.staging',
    );
    expect(
      manageSubscriptionUri(
        store: SubscriptionStore.appStore,
        packageName: 'com.mevora.app',
        productId: 'mevora_premium',
      ).toString(),
      'https://apps.apple.com/account/subscriptions',
    );
    expect(
      SubscriptionStore.forStatus(
        const PremiumStatus(isPremium: true, platform: 'ios'),
      ),
      SubscriptionStore.appStore,
    );
    expect(
      SubscriptionStore.forStatus(_premiumOnPlay),
      SubscriptionStore.googlePlay,
    );
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('paywall fits a small phone at large text — $locale', (
      tester,
    ) async {
      await _pump(
        tester,
        status: PremiumStatus.free,
        // The test font draws every glyph a full em wide, about twice the
        // real serif, and the shared plan tile gives its price column no
        // room to shrink. A seven-character price keeps this test about the
        // disclosures added here rather than about that tile.
        plans: const [
          _monthly,
          PremiumPlan(
            productId: 'mevora_premium',
            basePlanId: 'yearly',
            title: 'Premium Yearly',
            description: 'Everything in Premium',
            formattedPrice: '₺999,99',
            period: PremiumPlanPeriod.yearly,
          ),
        ],
        locale: locale,
        size: const Size(360, 640),
        textScale: 1.3,
      );
      // Lay out everything down to the legal links, not just the first fold.
      await tester.scrollUntilVisible(
        find.byKey(PurchaseLegalLinks.privacyKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('paywallRenewalDisclosure')), findsOneWidget);
    });

    testWidgets('Premium member view fits a small phone — $locale', (
      tester,
    ) async {
      await _pump(
        tester,
        status: _premiumOnPlay,
        locale: locale,
        size: const Size(360, 640),
        textScale: 1.3,
      );
      await tester.scrollUntilVisible(
        find.byKey(PurchaseLegalLinks.privacyKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('paywallManageSubscription')),
        findsOneWidget,
      );
    });
  }
}
