import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/location/domain/entities/location_screen_state.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/location/presentation/pages/location_permission_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/recording_location_analytics.dart';

final _l10n = lookupAppLocalizations(const Locale('tr'));

Widget _wrap(LocationController controller) {
  return LocationScope(
    repository: controller.repository,
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('tr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const LocationPermissionPage(),
    ),
  );
}

void main() {
  testWidgets('permission screen shows Turkish copy without coordinates', (
    tester,
  ) async {
    final controller = LocationController(
      repository: FakeLocationRepository(
        permission: LocationPermissionStatus.notDetermined,
      ),
      successHold: Duration.zero,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller));

    expect(find.text(_l10n.locationPermissionTitle), findsOneWidget);
    expect(find.text(_l10n.locationPermissionMessage), findsOneWidget);
    expect(find.text(_l10n.locationPermissionSub), findsOneWidget);
    expect(find.text(_l10n.useMyLocation), findsOneWidget);
    expect(find.text(_l10n.notNow), findsOneWidget);
    expect(find.text('41.0082'), findsNothing);
    expect(find.textContaining('28.9784'), findsNothing);
  });

  testWidgets('denied state explains matching needs location', (tester) async {
    final controller = LocationController(
      repository: FakeLocationRepository(),
      successHold: Duration.zero,
    )..screen = LocationScreenState.denied;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller));

    expect(find.text(_l10n.locationDeniedMessage), findsOneWidget);
    expect(find.text(_l10n.useMyLocation), findsOneWidget);
  });

  testWidgets('loading state shows locating copy', (tester) async {
    final controller = LocationController(
      repository: FakeLocationRepository(),
      successHold: Duration.zero,
    )..screen = LocationScreenState.locating;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller));

    expect(find.text(_l10n.locationLocating), findsOneWidget);
  });

  testWidgets('GPS off state offers settings', (tester) async {
    final controller = LocationController(
      repository: FakeLocationRepository(gpsEnabled: false),
      successHold: Duration.zero,
    )..screen = LocationScreenState.serviceDisabled;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller));

    expect(find.text(_l10n.gpsDisabledTitle), findsOneWidget);
    expect(find.text(_l10n.gpsDisabledMessage), findsOneWidget);
    expect(find.text(_l10n.openSettings), findsOneWidget);
  });

  testWidgets('error state shows retry without coordinates', (tester) async {
    final controller = LocationController(
      repository: FakeLocationRepository(),
      successHold: Duration.zero,
    )..screen = LocationScreenState.error
      ..errorMessage = _l10n.locationTimeoutMessage;
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller));

    expect(find.text(_l10n.locationUnavailableTitle), findsOneWidget);
    expect(find.text(_l10n.locationTimeoutMessage), findsOneWidget);
    expect(find.text(_l10n.tryAgain), findsOneWidget);
    expect(find.textContaining('41.'), findsNothing);
  });

  testWidgets('allow records analytics without lat lng', (tester) async {
    final analytics = RecordingLocationAnalytics();
    final repo = FakeLocationRepository(
      permission: LocationPermissionStatus.notDetermined,
    )..requestResult = LocationPermissionStatus.granted;
    final controller = LocationController(
      repository: repo,
      analytics: analytics,
      successHold: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.syncForUser('u1');
    await controller.allow();

    expect(analytics.events, contains('location_permission_requested'));
    expect(analytics.events, contains('location_permission_granted'));
    expect(analytics.events, contains('location_acquired'));
    expect(analytics.events.join(), isNot(contains('41.0082')));
    expect(repo.stored['u1'], isNotNull);
  });
}
