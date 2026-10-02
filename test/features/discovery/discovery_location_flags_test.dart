import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/testing/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/presentation/screens/location_permission_screen.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../picks/picks_fixtures.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// A location repository whose flags read can fail, the way Firestore does on
/// a cold start with no connection and `userSettings/{uid}` not in its cache.
class _UnreadableFlagsLocationRepository extends FakeLocationRepository {
  _UnreadableFlagsLocationRepository({super.permission});

  bool flagsReadable = false;
  int flagReads = 0;
  int flagWrites = 0;

  /// When set, a flags read waits for this before answering.
  Completer<void>? gate;

  /// When set, storing a position waits for this before answering — what a
  /// Firestore write does while the phone is offline.
  Completer<void>? persistGate;

  @override
  Future<Result<void>> persistOwnerLocation({
    required String uid,
    required GeoPosition position,
  }) async {
    await persistGate?.future;
    return super.persistOwnerLocation(uid: uid, position: position);
  }

  @override
  Future<Result<LocationFlags>> loadLocationFlags(String uid) async {
    flagReads += 1;
    await gate?.future;
    if (!flagsReadable) {
      return const Err(
        LocationFailure(
          'Location is currently unavailable.',
          kind: LocationErrorKind.network,
        ),
      );
    }
    return super.loadLocationFlags(uid);
  }

  @override
  Future<Result<void>> saveLocationFlags(LocationFlags next) {
    flagWrites += 1;
    return super.saveLocationFlags(next);
  }
}

const _locationOn = LocationFlags(
  uid: 'self',
  locationEnabled: true,
  locationOnboardingCompleted: true,
);

void main() {
  group('DiscoveryController with unreadable location flags', () {
    DiscoveryController build(
      FakeLocationRepository location, {
      bool skipExplanationIfAlreadyGranted = false,
      Duration locationFlagsTimeout = const Duration(seconds: 8),
    }) {
      final controller = DiscoveryController(
        uid: 'self',
        locationRepository: location,
        discoveryRepository: InMemoryDiscoveryRepository(
          seeds: const [
            DiscoverySeed(
              profile: UserProfile(uid: 'ada', displayName: 'Ada', age: 27),
              distanceKm: 4,
              distanceLabel: '4 km away',
            ),
          ],
        ),
        skipExplanationIfAlreadyGranted: skipExplanationIfAlreadyGranted,
        locationFlagsTimeout: locationFlagsTimeout,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('a flags read that never answers is treated as unread, not waited '
        'on forever', () async {
      // Seen on a device: offline with nothing cached, Firestore neither
      // answered nor failed, and the tab stayed on "Loading" until the
      // connection came back.
      final location = _UnreadableFlagsLocationRepository()
        ..flagsReadable = true
        ..flags['self'] = _locationOn
        ..gate = Completer<void>();
      addTearDown(() => location.gate!.complete());
      final controller = build(
        location,
        locationFlagsTimeout: const Duration(milliseconds: 20),
      );

      await controller.start().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('start() waited on the flags read'),
      );

      expect(controller.locationFlagsPending, isFalse);
      expect(controller.locationFlagsUnresolved, isTrue);
      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(location.flagWrites, 0);
      expect(location.captureCalls, 0);
    });

    test('a position that cannot be stored does not hold the tab', () async {
      // The device symptom: a member whose permission is granted but whose
      // flags are not marked complete has the position captured at start. The
      // write never came back offline, and neither did start().
      final location = _UnreadableFlagsLocationRepository()
        ..flagsReadable = true
        ..persistGate = Completer<void>();
      addTearDown(() => location.persistGate!.complete());
      final controller = build(
        location,
        skipExplanationIfAlreadyGranted: true,
        locationFlagsTimeout: const Duration(milliseconds: 20),
      );

      final started = controller.start();
      // While the position is being settled there is no question to answer.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.locationFlagsPending, isFalse);
      expect(controller.settlingGrantedLocation, isTrue);

      await started.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('start() waited on the location write'),
      );

      expect(controller.settlingGrantedLocation, isFalse);
      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(controller.state.candidates, isNotEmpty);
      expect(location.flagWrites, 0);
    });

    test('a read that timed out is settled by the next refresh', () async {
      final location = _UnreadableFlagsLocationRepository()
        ..flagsReadable = true
        ..flags['self'] = _locationOn
        ..gate = Completer<void>();
      final controller = build(
        location,
        locationFlagsTimeout: const Duration(milliseconds: 20),
      );
      await controller.start();
      expect(controller.locationFlagsUnresolved, isTrue);

      // The connection is back: the read answers again.
      location.gate!.complete();
      location.gate = null;
      await controller.refresh();

      expect(controller.locationFlagsUnresolved, isFalse);
      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(location.flags['self'], _locationOn);
      expect(location.flagWrites, 0);
    });

    test('a failed flags read is not answered with the location question, '
        'and nothing is saved', () async {
      final location = _UnreadableFlagsLocationRepository(
        permission: LocationPermissionStatus.denied,
      );
      final controller = build(location);
      await controller.start();

      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(location.flagWrites, 0);
      expect(location.flags, isEmpty);
      expect(location.requestPermissionCalls, 0);

      // The same path a member who finished location onboarding takes: the
      // deck simply loads.
      final onboarded = build(
        FakeLocationRepository(permission: LocationPermissionStatus.denied)
          ..flags['self'] = const LocationFlags(
            uid: 'self',
            locationOnboardingCompleted: true,
          ),
      );
      await onboarded.start();
      expect(onboarded.state.phase, controller.state.phase);
      expect(
        controller.state.candidates.map((c) => c.uid),
        onboarded.state.candidates.map((c) => c.uid),
      );
      expect(controller.state.candidates, isNotEmpty);
    });

    test('a failed flags read captures and stores no location either, even '
        'with the permission granted', () async {
      final location = _UnreadableFlagsLocationRepository();
      final controller = build(location, skipExplanationIfAlreadyGranted: true);
      await controller.start();

      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(location.captureCalls, 0);
      expect(location.persistCalls, 0);
      expect(location.flagWrites, 0);
    });

    test('after a failed read, the next refresh asks a member who was never '
        'asked', () async {
      final location = _UnreadableFlagsLocationRepository(
        permission: LocationPermissionStatus.denied,
      );
      final controller = build(location);
      await controller.start();
      expect(controller.state.phase, isNot(LocationPromptPhase.explanation));

      location.flagsReadable = true;
      await controller.refresh();

      expect(location.flagReads, 2);
      expect(controller.state.phase, LocationPromptPhase.explanation);
      expect(location.flagWrites, 0);

      // The answer is stored as on any first run.
      await controller.skipLocation();
      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(location.flags['self']?.locationOnboardingCompleted, isTrue);
      expect(location.flags['self']?.locationEnabled, isFalse);
    });

    test('a refresh that still cannot read the flags asks nothing and saves '
        'nothing', () async {
      final location = _UnreadableFlagsLocationRepository(
        permission: LocationPermissionStatus.denied,
      );
      final controller = build(location);
      await controller.start();
      await controller.refresh();

      expect(location.flagReads, 2);
      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(location.flagWrites, 0);
      expect(location.flags, isEmpty);
    });

    test('after a failed read, a member who had location on is not asked and '
        'keeps it on', () async {
      final location = _UnreadableFlagsLocationRepository()
        ..flags['self'] = _locationOn;
      final controller = build(location);
      await controller.start();
      expect(controller.state.phase, isNot(LocationPromptPhase.explanation));

      location.flagsReadable = true;
      await controller.refresh();

      expect(location.flagReads, 2);
      expect(controller.state.phase, LocationPromptPhase.ready);
      expect(controller.declinedLocation, isFalse);
      expect(location.flagWrites, 0);
      expect(location.flags['self'], same(_locationOn));

      // The question is settled: later refreshes do not read the flags again.
      await controller.refresh();
      expect(location.flagReads, 2);
      expect(location.flagWrites, 0);
    });

    test(
      'refreshes that overlap while the flags are unread share one read',
      () async {
        final location = _UnreadableFlagsLocationRepository(
          permission: LocationPermissionStatus.denied,
        );
        final controller = build(location);
        await controller.start();

        location.gate = Completer<void>();
        final first = controller.refresh();
        final second = controller.refresh();
        location.flagsReadable = true;
        location.gate!.complete();
        await Future.wait([first, second]);

        expect(location.flagReads, 2);
        expect(controller.state.phase, LocationPromptPhase.explanation);
      },
    );

    test(
      'a first-run member whose flags can be read is asked as before',
      () async {
        final location = _UnreadableFlagsLocationRepository(
          permission: LocationPermissionStatus.denied,
        )..flagsReadable = true;
        final controller = build(location);
        await controller.start();

        expect(controller.state.phase, LocationPromptPhase.explanation);
        expect(location.flagReads, 1);
        expect(location.flagWrites, 0);
        expect(location.requestPermissionCalls, 0);
        expect(controller.state.candidates, isEmpty);
      },
    );
  });

  group('Picks tab with unreadable location flags', () {
    Widget app(Widget home) {
      return MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      );
    }

    late FakeMevoraPicksRepository picksRepository;

    Future<DiscoveryController> pumpTab(
      WidgetTester tester,
      FakeLocationRepository location,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final discovery = DiscoveryController(
        uid: 'self',
        locationRepository: location,
        discoveryRepository: InMemoryDiscoveryRepository(),
        loadDeckOnStart: false,
      );
      picksRepository = FakeMevoraPicksRepository(
        batchOf([pickPayload(uid: 'zeynep')]),
      )..failLoads = true;
      final picks = MevoraPicksController(
        repository: picksRepository,
        removalDuration: Duration.zero,
      );
      addTearDown(discovery.dispose);
      addTearDown(picks.dispose);
      await tester.pumpWidget(
        app(DiscoveryPage(controller: discovery, picksController: picks)),
      );
      return discovery;
    }

    testWidgets('offline shows the Picks load error, not the location '
        'question; Retry asks once the flags can be read', (tester) async {
      final location = _UnreadableFlagsLocationRepository(
        permission: LocationPermissionStatus.denied,
      );
      final discovery = await pumpTab(tester, location);
      await tester.pumpAndSettle();

      expect(find.text(_en.picksLoadErrorTitle), findsOneWidget);
      expect(find.byType(LocationPermissionScreen), findsNothing);
      // The first Picks load is not a retry of the flags.
      expect(location.flagReads, 1);
      expect(location.flagWrites, 0);

      // Still offline: Retry tries the flags again and still asks nothing.
      await tester.tap(find.text(_en.retry));
      await tester.pumpAndSettle();
      expect(find.text(_en.picksLoadErrorTitle), findsOneWidget);
      expect(find.byType(LocationPermissionScreen), findsNothing);
      expect(location.flagReads, 2);
      expect(location.flagWrites, 0);

      // Back online, and this member was never asked.
      location.flagsReadable = true;
      picksRepository.failLoads = false;
      await tester.tap(find.text(_en.retry));
      await tester.pumpAndSettle();
      expect(find.byType(LocationPermissionScreen), findsOneWidget);
      expect(location.flagReads, 3);
      expect(location.flagWrites, 0);

      // Answering stores the choice, and Picks load again now that location
      // is settled.
      final loadsBeforeAnswer = picksRepository.loads;
      await tester.tap(find.text(_en.notNow));
      await tester.pumpAndSettle();
      expect(discovery.state.phase, LocationPromptPhase.ready);
      expect(location.flags['self']?.locationOnboardingCompleted, isTrue);
      expect(location.flags['self']?.locationEnabled, isFalse);
      expect(picksRepository.loads, loadsBeforeAnswer + 1);
      expect(find.text('Zeynep, 25'), findsOneWidget);
    });

    testWidgets('a member who had location on gets their Picks back on Retry, '
        'with the flags untouched', (tester) async {
      final location = _UnreadableFlagsLocationRepository()
        ..flags['self'] = _locationOn;
      await pumpTab(tester, location);
      await tester.pumpAndSettle();

      expect(find.text(_en.picksLoadErrorTitle), findsOneWidget);
      expect(find.byType(LocationPermissionScreen), findsNothing);
      // Nothing about location is captured while the flags are unknown.
      expect(location.captureCalls, 0);
      expect(location.persistCalls, 0);

      location.flagsReadable = true;
      picksRepository.failLoads = false;
      await tester.tap(find.text(_en.retry));
      await tester.pumpAndSettle();

      expect(find.byType(LocationPermissionScreen), findsNothing);
      expect(find.text('Zeynep, 25'), findsOneWidget);
      expect(location.flagReads, 2);
      expect(location.flagWrites, 0);
      expect(location.flags['self'], same(_locationOn));
    });

    testWidgets('the location question is not offered while the first flags '
        'read is still running', (tester) async {
      final location = _UnreadableFlagsLocationRepository()
        ..flags['self'] = _locationOn
        ..gate = Completer<void>();
      await pumpTab(tester, location);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(location.flagReads, 1);
      expect(find.byType(LocationPermissionScreen), findsNothing);
      expect(find.text(_en.notNow), findsNothing);

      // The read gives up: the tab moves on to its ordinary load error.
      location.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text(_en.picksLoadErrorTitle), findsOneWidget);
      expect(find.byType(LocationPermissionScreen), findsNothing);
      expect(location.flagWrites, 0);
    });
  });
}
