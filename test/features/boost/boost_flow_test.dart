import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/boost/presentation/pages/boost_screen.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_button.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_purchase_repository.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

void main() {
  testWidgets('open boost, buy a duration pack, verify, return to discovery', (
    tester,
  ) async {
    final purchases = FakePurchaseRepository();
    final discovery = InMemoryDiscoveryRepository(
      seeds: const [
        DiscoverySeed(
          profile: UserProfile(uid: 'ada', displayName: 'Ada', age: 27),
          distanceKm: 3,
          distanceLabel: '3 km away',
        ),
      ],
    );
    final discoveryController = DiscoveryController(
      uid: 'u1',
      locationRepository: FakeLocationRepository(
        permission: LocationPermissionStatus.granted,
      ),
      discoveryRepository: discovery,
      purchaseRepository: purchases,
    );
    addTearDown(discoveryController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: BoostScope(
          repository: purchases,
          child: DiscoveryPage(controller: discoveryController),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(BoostButton), findsOneWidget);

    await tester.tap(find.byType(BoostButton));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(BoostScreen), findsOneWidget);
    expect(find.text('₺99,99'), findsOneWidget);

    await tester.tap(find.text(_l10n.boostBuyPack).first);
    await tester.pump();
    await tester.pump();
    expect(purchases.verifyCalled, isTrue);
    expect(find.text(_l10n.boostSuccessTitle), findsOneWidget);
    expect(purchases.activeBoost?.status.name, 'active');

    await tester.tap(find.text(_l10n.boostBackToDiscovery));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DiscoveryPage), findsOneWidget);
    expect(find.text('Ada, 27'), findsOneWidget);
    expect(discoveryController.state.activeBoost, isNotNull);
    expect(purchases.activeReads, greaterThan(0));
  });
}
