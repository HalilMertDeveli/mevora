import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_card_stack.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/presentation/screens/location_permission_screen.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));
final _en = lookupAppLocalizations(const Locale('en'));

Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('permission screen uses the Turkish explanation copy', (tester) async {
    await tester.pumpWidget(
      wrap(const LocationPermissionScreen(), locale: const Locale('tr')),
    );
    expect(find.text(_tr.locationPermissionTitle), findsOneWidget);
    expect(find.text(_tr.locationPermissionMessage), findsOneWidget);
    expect(find.text(_tr.useMyLocation), findsOneWidget);
    expect(find.text(_tr.notNow), findsOneWidget);
  });

  testWidgets('discovery card shows name, age, distance, and compatibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          height: 520,
          child: DiscoveryProfileCard(
            candidate: DiscoveryCandidate(
              uid: 'ada',
              displayName: 'Ada',
              age: 27,
              distanceLabel: '3.8 km away',
              compatibilityScore: 82,
              interests: ['travel', 'music'],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Ada, 27'), findsOneWidget);
    expect(find.textContaining('3.8 km away'), findsOneWidget);
    expect(find.textContaining('82%'), findsOneWidget);
    expect(find.text('travel'), findsOneWidget);
    expect(find.text('41.0082'), findsNothing);
  });

  testWidgets('demo profile cards show a portrait, not a numeral placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          height: 520,
          width: 360,
          child: DiscoveryProfileCard(
            candidate: DiscoveryCandidate(
              uid: 'mock-08',
              displayName: 'Burak',
              age: 28,
              city: 'Eskisehir',
              photos: ['assets/images/portraits/mock-08.jpg'],
              compatibilityScore: 73,
              bio: 'Mimar.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Burak, 28'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
      isNot(contains('0')),
    );
  });

  testWidgets('discovery stack paints only the front person', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          height: 520,
          width: 360,
          child: DiscoveryCardStack(
            candidates: const [
              DiscoveryCandidate(
                uid: 'mock-08',
                displayName: 'Burak',
                age: 28,
                city: 'Eskisehir',
                bio: 'Mimar.',
              ),
              DiscoveryCandidate(
                uid: 'mock-09',
                displayName: 'Ece',
                age: 30,
                city: 'İstanbul',
                bio: 'Proje Yöneticisi',
              ),
            ],
            dragOffset: Offset.zero,
            swipeDirection: DiscoverySwipeDirection.none,
            animateOut: false,
            showLikeBurst: false,
            onDragUpdate: (_) {},
            onDragEnd: () {},
            onCardTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(DiscoveryProfileCard), findsOneWidget);
    expect(find.text('Burak, 28'), findsOneWidget);
    expect(find.text('Ece, 30'), findsNothing);
    expect(find.text('İstanbul'), findsNothing);
    expect(find.text('Proje Yöneticisi'), findsNothing);
  });

  testWidgets('GPS disabled shows a non-crashing empty state', (tester) async {
    final controller = DiscoveryController(
      uid: 'self',
      locationRepository: FakeLocationRepository(gpsEnabled: false),
      discoveryRepository: InMemoryDiscoveryRepository(
        seeds: const [
          DiscoverySeed(
            profile: UserProfile(uid: 'ada', displayName: 'Ada', age: 27),
            distanceKm: 3,
            distanceLabel: '3 km away',
          ),
        ],
      ),
      skipExplanationIfAlreadyGranted: false,
    );
    await tester.pumpWidget(wrap(DiscoveryPage(controller: controller)));
    await tester.pump();
    await tester.pump();
    await controller.useMyLocation();
    await tester.pump();
    expect(find.text(_en.gpsDisabledTitle), findsOneWidget);
  });

  testWidgets('location error view stays usable', (tester) async {
    await tester.pumpWidget(
      wrap(
        MevoraErrorView(
          title: _en.locationUnavailableTitle,
          message: _en.locationTimeoutMessage,
        ),
      ),
    );
    expect(find.text(_en.locationUnavailableTitle), findsOneWidget);
  });

  testWidgets('offline discovery shows a retryable error without coordinates', (
    tester,
  ) async {
    final location = FakeLocationRepository()
      ..flags['self'] = const LocationFlags(
        uid: 'self',
        locationEnabled: false,
        locationOnboardingCompleted: true,
      );
    final controller = DiscoveryController(
      uid: 'self',
      locationRepository: location,
      discoveryRepository: _OfflineDiscovery(),
    );
    await tester.pumpWidget(wrap(DiscoveryPage(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byType(MevoraErrorView), findsOneWidget);
    expect(find.text(_en.networkError), findsOneWidget);
    expect(find.text('41.0082'), findsNothing);
  });

  testWidgets('permanently denied permission is explained', (tester) async {
    final controller = DiscoveryController(
      uid: 'self',
      locationRepository: FakeLocationRepository(
        permission: LocationPermissionStatus.permanentlyDenied,
      ),
      discoveryRepository: InMemoryDiscoveryRepository(),
      skipExplanationIfAlreadyGranted: false,
    );
    await tester.pumpWidget(wrap(DiscoveryPage(controller: controller)));
    await tester.pump();
    await tester.pump();
    expect(find.text(_en.locationSettingsTitle), findsOneWidget);
  });
}

class _OfflineDiscovery implements DiscoveryRepository {
  @override
  Future<Result<DiscoveryPageResult>> getCandidates({
    required DiscoveryRadius radius,
    String? cursor,
    int limit = 10,
  }) async {
    return Err(NetworkFailure(_en.networkError));
  }

  @override
  Future<Result<DiscoveryDecisionResult>> recordDecision({
    required String candidateUid,
    required DiscoveryDecision decision,
  }) async {
    return const Success(DiscoveryDecisionResult());
  }
}
