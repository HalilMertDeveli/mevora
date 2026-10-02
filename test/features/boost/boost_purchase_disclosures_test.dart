import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/boost/domain/usecases/get_active_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_product.dart';
import 'package:mevora/features/boost/domain/usecases/purchase_boost.dart';
import 'package:mevora/features/boost/domain/usecases/verify_boost_purchase.dart';
import 'package:mevora/features/boost/presentation/controllers/purchase_controller.dart';
import 'package:mevora/features/boost/presentation/pages/boost_screen.dart';
import 'package:mevora/features/subscription/presentation/widgets/purchase_legal_links.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_purchase_repository.dart';

/// The Boost screen inside a real router, so the legal links go where the app
/// sends them.
Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Size size = const Size(800, 1800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = FakePurchaseRepository();
  final controller = PurchaseController(
    userId: 'u1',
    getBoostProduct: GetBoostProduct(repository),
    purchaseBoost: PurchaseBoost(repository),
    verifyBoostPurchase: VerifyBoostPurchase(repository),
    getActiveBoost: GetActiveBoost(repository),
    repository: repository,
  );
  addTearDown(controller.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.boost,
    routes: [
      GoRoute(
        path: AppRoutes.boost,
        builder: (context, state) => BoostScreen(controller: controller),
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
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('Boost says it is a one-time purchase that does not renew', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(en.boostOneTimePurchaseNote), findsOneWidget);
    expect(en.boostOneTimePurchaseNote, contains('one-time'));
    expect(en.boostOneTimePurchaseNote, contains('does not renew'));
    // The store price and restore are still there.
    expect(find.text('₺99,99'), findsOneWidget);
    expect(find.text(en.restorePurchases), findsOneWidget);
  });

  testWidgets('Terms and Privacy are links that open the in-app legal pages', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      tester.getSemantics(find.byKey(PurchaseLegalLinks.termsKey)),
      isSemantics(label: en.termsOfService, isLink: true, hasTapAction: true),
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

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('Boost purchase fits a small phone at large text — $locale', (
      tester,
    ) async {
      await _pump(
        tester,
        locale: locale,
        size: const Size(360, 640),
        textScale: 1.3,
      );
      await tester.scrollUntilVisible(
        find.byKey(PurchaseLegalLinks.privacyKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('boostOneTimePurchaseNote')), findsOneWidget);
    });
  }
}
