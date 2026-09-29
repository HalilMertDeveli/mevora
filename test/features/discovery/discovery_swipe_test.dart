import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
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
      // Backend reasons arrive as fixed English codes.
      compatibilityReasons: ['Shared interests'],
    );

    await tester.pumpWidget(
      wrap(const SizedBox(height: 620, child: DiscoveryProfileCard(candidate: candidate))),
    );
    expect(find.text('Elif, 26'), findsOneWidget);
    expect(find.text('Istanbul'), findsOneWidget);
    // Why-you-fit strip: the reason in words, the score as a quiet ring.
    expect(find.text(_en.compatReasonSomeSharedInterests), findsOneWidget);
    expect(find.text('Shared interests'), findsNothing);
    expect(find.byType(CompatibilityRing), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
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

    await tester.tap(find.byTooltip(_en.pass));
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
    // Photo PageView is above the details ListView — scroll the list only.
    await tester.scrollUntilVisible(
      find.text(_en.compatWhyThisPerson(candidate.displayName)),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text(_en.compatWhyThisPerson(candidate.displayName)),
      findsOneWidget,
    );
    // Free-text reasons the backend never sends are not shown raw.
    expect(find.text('Both love specialty coffee'), findsNothing);
    // The score is a quiet ring inside the why-you-fit card, not a badge.
    expect(find.byType(CompatibilityRing), findsWidgets);
  });

  testWidgets('profile photo carousel swipes to second photo', (tester) async {
    const candidate = DiscoveryCandidate(
      uid: 'mock-photos',
      displayName: 'PhotoUser',
      age: 28,
      photos: [
        'mock://mock-01/0',
        'mock://mock-02/0',
        'mock://mock-03/0',
      ],
    );

    await tester.pumpWidget(
      wrap(const DiscoveryProfileDetailsPage(candidate: candidate)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_photoCounter(_en.photoCounter(1, 3)), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_photoCounter(_en.photoCounter(2, 3)), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_photoCounter(_en.photoCounter(3, 3)), findsOneWidget);
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

Finder _photoCounter(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);
