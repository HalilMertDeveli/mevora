import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/location/domain/entities/location_screen_state.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/location/presentation/pages/location_permission_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

Widget _wrap(LocationController controller, Locale locale) {
  return LocationScope(
    repository: controller.repository,
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const LocationPermissionPage(),
    ),
  );
}

/// Puts the controller into the error state carrying a raw data-layer string,
/// which is what LocationController.errorMessage actually holds.
LocationController _erroredController(String? rawMessage) {
  final controller = LocationController(
    repository: FakeLocationRepository(),
    successHold: Duration.zero,
  )
    ..screen = LocationScreenState.error
    ..errorMessage = rawMessage;
  return controller;
}

void main() {
  testWidgets('timeout error is fully English in an English session', (
    tester,
  ) async {
    final controller = _erroredController(AppStrings.locationTimeoutMessage);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller, const Locale('en')));
    await tester.pump();

    expect(find.text(_en.locationUnavailableTitle), findsOneWidget);
    expect(find.text(_en.locationTimeoutMessage), findsOneWidget);
    // The raw Turkish constant must not reach the screen.
    expect(find.text(AppStrings.locationTimeoutMessage), findsNothing);
    expect(find.text(_tr.locationTimeoutMessage), findsNothing);
  });

  testWidgets('timeout error is fully Turkish in a Turkish session', (
    tester,
  ) async {
    final controller = _erroredController(AppStrings.locationTimeoutMessage);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller, const Locale('tr')));
    await tester.pump();

    expect(find.text(_tr.locationUnavailableTitle), findsOneWidget);
    expect(find.text(_tr.locationTimeoutMessage), findsOneWidget);
    expect(find.text(_en.locationTimeoutMessage), findsNothing);
  });

  testWidgets('every raw location error constant is localized in English', (
    tester,
  ) async {
    // FailureMessages.of can emit any of these for a LocationFailure.
    final cases = <String, String>{
      AppStrings.locationTimeoutMessage: _en.locationTimeoutMessage,
      AppStrings.locationNetworkMessage: _en.locationNetworkMessage,
      AppStrings.gpsDisabledMessage: _en.gpsDisabledMessage,
      AppStrings.locationDeniedMessage: _en.locationDeniedMessage,
      AppStrings.locationSettingsMessage: _en.locationSettingsMessage,
      AppStrings.locationUnavailableTitle: _en.locationUnavailableTitle,
    };

    for (final entry in cases.entries) {
      final controller = _erroredController(entry.key);
      await tester.pumpWidget(_wrap(controller, const Locale('en')));
      await tester.pump();

      expect(
        find.text(entry.value),
        findsWidgets,
        reason: 'raw "${entry.key}" must render as "${entry.value}"',
      );
      expect(
        find.text(entry.key),
        findsNothing,
        reason: 'raw "${entry.key}" leaked to the UI untranslated',
      );
      controller.dispose();
    }
  });

  testWidgets('an unrecognised error falls back without leaking Turkish', (
    tester,
  ) async {
    final controller = _erroredController('some-unmapped-backend-string');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller, const Locale('en')));
    await tester.pump();

    // Title stays localized; the page must still render an error state.
    expect(find.text(_en.locationUnavailableTitle), findsOneWidget);
    expect(find.text(_en.tryAgain), findsOneWidget);
  });

  testWidgets('a null error message falls back to the localized timeout copy', (
    tester,
  ) async {
    final controller = _erroredController(null);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller, const Locale('en')));
    await tester.pump();

    expect(find.text(_en.locationTimeoutMessage), findsOneWidget);
  });
}
