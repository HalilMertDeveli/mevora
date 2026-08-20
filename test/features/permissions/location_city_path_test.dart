import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/location/domain/entities/location_screen_state.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/location/presentation/pages/location_permission_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('denied location offers city selection without blocking', (
    tester,
  ) async {
    final controller = LocationController(
      repository: FakeLocationRepository(),
      successHold: Duration.zero,
    )..screen = LocationScreenState.denied;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      LocationScope(
        repository: controller.repository,
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const LocationPermissionPage(),
        ),
      ),
    );

    expect(find.text(l10n.selectCityInstead), findsOneWidget);
    expect(find.text(l10n.notNow), findsOneWidget);
    await tester.tap(find.text(l10n.selectCityInstead));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.citySelectTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
