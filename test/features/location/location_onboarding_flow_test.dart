import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/app.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';

void main() {
  const environment = AppEnvironment.development;
  const logger = AppLogger(environment: environment);
  final l10n = lookupAppLocalizations(const Locale('tr'));

  Future<void> pumpApp(
    WidgetTester tester, {
    required AuthUser user,
    required LocationController location,
  }) async {
    final auth = AuthController(
      authRepository: FakeAuthRepository(user: user),
      userDocumentRepository: FakeUserDocumentRepository(
        complete: user.profileCompleted,
      ),
      logger: logger,
    );
    addTearDown(auth.dispose);
    final language = LanguageController(
      repository: LanguageRepository(
        local: MemoryLanguageDataSource(languageCode: 'tr'),
      ),
      deviceLocale: const Locale('de'),
    );
    await language.load();
    await tester.pumpWidget(
      MevoraApp(
        config: const AppConfig(environment: environment),
        logger: logger,
        authController: auth,
        locationController: location,
        locationRepository: location.repository,
        languageController: language,
        onboardingServices: createFakeOnboardingServices(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('new user auth opens location permission before onboarding', (
    tester,
  ) async {
    final repo = FakeLocationRepository(
      permission: LocationPermissionStatus.notDetermined,
    )..requestResult = LocationPermissionStatus.granted;
    final location = LocationController(
      repository: repo,
      successHold: Duration.zero,
    );
    addTearDown(location.dispose);

    await pumpApp(
      tester,
      user: const AuthUser(id: 'new-1'),
      location: location,
    );

    expect(find.text(l10n.locationPermissionTitle), findsOneWidget);
    await tester.tap(find.text(l10n.useMyLocation));
    await tester.pumpAndSettle();

    expect(repo.stored['new-1'], isNotNull);
    expect(repo.flags['new-1']?.locationEnabled, isTrue);
    expect(find.text(l10n.onboardingTitle), findsOneWidget);
    expect(find.text('41.0082'), findsNothing);
  });

  testWidgets('existing user with location goes to the main app', (
    tester,
  ) async {
    final repo = FakeLocationRepository();
    repo.stored['old-1'] = StoredUserLocation(
      uid: 'old-1',
      latitude: 41.0082,
      longitude: 28.9784,
      geohash: 'sxk',
      updatedAt: DateTime.utc(2026, 8, 18),
    );
    repo.flags['old-1'] = const LocationFlags(
      uid: 'old-1',
      locationEnabled: true,
      locationOnboardingCompleted: true,
    );
    final location = LocationController(
      repository: repo,
      successHold: Duration.zero,
    );
    addTearDown(location.dispose);

    await pumpApp(
      tester,
      user: const AuthUser(
        id: 'old-1',
        profileCompleted: true,
        onboardingCompleted: true,
      ),
      location: location,
    );

    expect(find.text(l10n.locationPermissionTitle), findsNothing);
    expect(find.text('Mevora'), findsWidgets);
  });

  testWidgets('existing user without location sees the flow once then skips', (
    tester,
  ) async {
    final repo = FakeLocationRepository(
      permission: LocationPermissionStatus.notDetermined,
    );
    final location = LocationController(
      repository: repo,
      successHold: Duration.zero,
    );
    addTearDown(location.dispose);

    await pumpApp(
      tester,
      user: const AuthUser(
        id: 'old-2',
        profileCompleted: true,
        onboardingCompleted: true,
      ),
      location: location,
    );

    expect(find.text(l10n.locationPermissionTitle), findsOneWidget);
    await tester.tap(find.text(l10n.notNow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repo.flags['old-2']?.locationOnboardingCompleted, isTrue);
    expect(
      find.text(l10n.locationPermissionTitle).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('denied forever opens settings copy not a looping dialog', (
    tester,
  ) async {
    final repo = FakeLocationRepository(
      permission: LocationPermissionStatus.permanentlyDenied,
    );
    final location = LocationController(
      repository: repo,
      successHold: Duration.zero,
    );
    addTearDown(location.dispose);

    await pumpApp(
      tester,
      user: const AuthUser(id: 'denied-1'),
      location: location,
    );

    expect(find.text(l10n.locationSettingsTitle), findsOneWidget);
    expect(find.text(l10n.openSettings), findsOneWidget);
    expect(repo.requestPermissionCalls, 0);
  });

  testWidgets('GPS off shows settings without requesting permission', (
    tester,
  ) async {
    final repo = FakeLocationRepository(gpsEnabled: false);
    final location = LocationController(
      repository: repo,
      successHold: Duration.zero,
    );
    addTearDown(location.dispose);

    await pumpApp(
      tester,
      user: const AuthUser(id: 'gps-off'),
      location: location,
    );

    expect(find.text(l10n.gpsDisabledTitle), findsOneWidget);
    expect(repo.requestPermissionCalls, 0);
  });
}
