import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/boost/domain/entities/purchase_flow_state.dart';
import 'package:mevora/features/boost/domain/usecases/get_active_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_product.dart';
import 'package:mevora/features/boost/domain/usecases/purchase_boost.dart';
import 'package:mevora/features/boost/domain/usecases/verify_boost_purchase.dart';
import 'package:mevora/features/boost/presentation/controllers/purchase_controller.dart';
import 'package:mevora/features/boost/presentation/pages/boost_screen.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_button.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_purchase_repository.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

PurchaseController controllerFor(FakePurchaseRepository repository) {
  return PurchaseController(
    userId: 'u1',
    getBoostProduct: GetBoostProduct(repository),
    purchaseBoost: PurchaseBoost(repository),
    verifyBoostPurchase: VerifyBoostPurchase(repository),
    getActiveBoost: GetActiveBoost(repository),
    repository: repository,
  );
}

void main() {
  testWidgets('BoostScreen shows copy, duration, localized price, and CTA', (
    tester,
  ) async {
    final repository = FakePurchaseRepository();
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(BoostScreen(controller: controller)));
    await tester.pump();
    await tester.pump();
    expect(find.text(_l10n.boostTitle), findsWidgets);
    expect(find.text(_l10n.boostSubtitle), findsOneWidget);
    expect(find.text(_l10n.boostDuration), findsOneWidget);
    expect(find.text('₺29,99'), findsOneWidget);
    expect(find.text(_l10n.boostActivate), findsOneWidget);
    expect(find.text(_l10n.boostSuccessTitle), findsNothing);
  });

  testWidgets('Boost button is visible', (tester) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          appBar: AppBar(
            actions: [BoostButton(onPressed: () {})],
          ),
        ),
      ),
    );
    expect(find.byType(BoostButton), findsOneWidget);
  });

  testWidgets('purchasing then verifying shows loading copy', (tester) async {
    final repository = FakePurchaseRepository();
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await controller.load();
    controller.state = controller.state.copyWith(
      status: PurchaseUiStatus.purchasing,
    );
    await tester.pumpWidget(wrap(BoostScreen(controller: controller)));
    await tester.pump();
    expect(find.text(_l10n.boostPurchasing), findsOneWidget);

    controller.state = controller.state.copyWith(
      status: PurchaseUiStatus.verifying,
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.text(_l10n.boostVerifying), findsOneWidget);
  });

  testWidgets('success copy appears only after verify', (tester) async {
    final repository = FakePurchaseRepository();
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(BoostScreen(controller: controller)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text(_l10n.boostActivate));
    await tester.pump();
    await tester.pump();
    expect(find.text(_l10n.boostSuccessTitle), findsOneWidget);
    expect(find.text(_l10n.boostSuccessMessage), findsOneWidget);
    expect(repository.verifyCalled, isTrue);
  });

  testWidgets('error state is human and has retry', (tester) async {
    final repository = FakePurchaseRepository(
      productFailure: PurchaseFailure(
        _l10n.boostStoreUnavailable,
        kind: PurchaseErrorKind.unavailable,
      ),
    );
    final controller = controllerFor(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(wrap(BoostScreen(controller: controller)));
    await tester.pump();
    await tester.pump();
    expect(find.text(_l10n.boostStoreUnavailable), findsOneWidget);
    expect(find.textContaining('StoreKit'), findsNothing);
    expect(find.textContaining('Billing'), findsNothing);
  });
}
