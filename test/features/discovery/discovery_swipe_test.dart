import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('discovery card shows compatibility and city', (tester) async {
    const candidate = DiscoveryCandidate(
      uid: 'mock-01',
      displayName: 'Elif',
      age: 26,
      city: 'Istanbul',
      bio: 'Coffee lover',
      compatibilityScore: 88,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
      interests: ['art', 'coffee'],
      compatibilityReasons: ['Shared interest in coffee culture'],
    );

    await tester.pumpWidget(
      wrap(const SizedBox(height: 620, child: DiscoveryProfileCard(candidate: candidate))),
    );
    expect(find.text('Elif, 26'), findsOneWidget);
    expect(find.text('Istanbul'), findsOneWidget);
    expect(find.text(_en.compatDiscoverBadge(88)), findsOneWidget);
    expect(find.text('Coffee lover'), findsOneWidget);
  });

  testWidgets('action buttons trigger controller methods', (tester) async {
    final discovery = MockDiscoveryRepository();
    final controller = DiscoveryController(
      uid: 'self',
      locationRepository: FakeLocationRepository(
        permission: LocationPermissionStatus.denied,
      ),
      discoveryRepository: discovery,
    );
    await controller.skipLocation();
    await tester.pumpWidget(wrap(DiscoveryPage(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(discovery.passed, isNotEmpty);
  });

  testWidgets('empty state shows seen everyone copy', (tester) async {
    final discovery = MockDiscoveryRepository();
    final controller = DiscoveryController(
      uid: 'self',
      locationRepository: FakeLocationRepository(
        permission: LocationPermissionStatus.denied,
      ),
      discoveryRepository: discovery,
    );
    await controller.skipLocation();
    await controller.setRadius(DiscoveryRadius.km50);
    while (controller.state.current != null) {
      await controller.onPass(controller.state.current!.uid);
    }
    await tester.pumpWidget(wrap(DiscoveryPage(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text(_en.discoverySeenEveryoneTitle), findsOneWidget);
    expect(find.text(_en.restartDemo), findsOneWidget);
  });

  testWidgets('profile details shows compatibility section', (tester) async {
    const candidate = DiscoveryCandidate(
      uid: 'mock-07',
      displayName: 'Selin',
      age: 25,
      city: 'Istanbul',
      compatibilityScore: 91,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
      sharedInterests: ['coffee', 'film'],
      compatibilityReasons: [
        'Strong shared interests in film',
        'Both love specialty coffee',
      ],
    );

    await tester.pumpWidget(
      wrap(const DiscoveryProfileDetailsPage(candidate: candidate)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(_en.whyYoureSeeingThis),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_en.whyYoureSeeingThis), findsOneWidget);
    expect(find.text(_en.compatDiscoverBadge(91)), findsWidgets);
  });

  testWidgets('discovery supports dark theme layout', (tester) async {
    const candidate = DiscoveryCandidate(
      uid: 'mock-02',
      displayName: 'Deniz',
      age: 29,
      compatibilityScore: 76,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: SizedBox(
            height: 620,
            child: DiscoveryProfileCard(candidate: candidate),
          ),
        ),
      ),
    );
    expect(find.text('Deniz, 29'), findsOneWidget);
  });
}
