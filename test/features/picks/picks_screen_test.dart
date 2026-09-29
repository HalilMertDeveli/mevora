import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/discovery/data/repositories/in_memory_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';
import 'package:mevora/features/picks/presentation/widgets/picks_view.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'picks_fixtures.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget _app(Widget home, {double textScale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
}

List<Map<String, dynamic>> _mixedBatch() => [
  pickPayload(
    uid: 'zeynep',
    name: 'Zeynep',
    pickType: 'humorMatch',
    labels: const ['humorMatch', 'bestOverall'],
    humorScore: 92,
    reasons: [
      {'type': 'humor', 'score': 92, 'strength': 'strong', 'meta': <String, Object>{}},
      {'type': 'relationship', 'score': null, 'strength': 'strong', 'meta': <String, Object>{}},
      {'type': 'overall', 'score': 89, 'strength': 'strong', 'meta': <String, Object>{}},
    ],
    overall: 89,
  ),
  pickPayload(
    uid: 'deniz',
    name: 'Deniz',
    pickType: 'unexpectedMatch',
    rank: 1,
    overall: 76,
  ),
  pickPayload(
    uid: 'ece',
    name: 'Ece',
    pickType: 'musicMatch',
    rank: 2,
    reasons: [
      {
        'type': 'music',
        'score': 72,
        'strength': 'notable',
        'meta': {'artists': 4},
      },
    ],
  ),
];

void main() {
  group('PicksView', () {
    late FakeMevoraPicksRepository repository;
    late MevoraPicksController controller;
    var discoverMoreTaps = 0;
    final opened = <String>[];

    Future<void> pumpView(
      WidgetTester tester, {
      double textScale = 1.0,
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PicksView(
              controller: controller,
              onOpenProfile: (pick) => opened.add(pick.uid),
              onDiscoverMore: () => discoverMoreTaps++,
            ),
          ),
          textScale: textScale,
        ),
      );
      await controller.load();
      await tester.pumpAndSettle();
    }

    setUp(() {
      discoverMoreTaps = 0;
      opened.clear();
      repository = FakeMevoraPicksRepository(batchOf(_mixedBatch()));
      controller = MevoraPicksController(
        repository: repository,
        removalDuration: Duration.zero,
      );
    });

    tearDown(() => controller.dispose());

    testWidgets('frames the set as chosen for the member, with reasons', (
      tester,
    ) async {
      await pumpView(tester);
      expect(find.text(_en.picksHeadline), findsOneWidget);
      expect(find.text(_en.picksIntroCount(3)), findsOneWidget);
      expect(find.text('Zeynep, 25'), findsOneWidget);
      expect(find.text(_en.pickTypeHumorMatch), findsOneWidget);
      expect(
        find.text('Your humor profiles are 92% compatible.'),
        findsOneWidget,
      );
      // The score is the compatibility ring, as on Discover.
      expect(
        find.descendant(
          of: find.byType(CompatibilityRing),
          matching: find.text('89'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Pass removes the card; tapping the card opens, not decides', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.tap(find.text('Zeynep, 25'));
      await tester.pump();
      expect(opened, ['zeynep']);
      expect(repository.decisions, isEmpty);

      final pass = find.bySemanticsLabel(_en.picksPassSemantics('Zeynep'));
      // The decision bar sits under the reason, below the first fold.
      await tester.ensureVisible(pass);
      await tester.pumpAndSettle();
      await tester.tap(pass);
      await tester.pumpAndSettle();
      expect(repository.decisions, [('zeynep', DiscoveryDecision.pass)]);
      expect(find.text('Zeynep, 25'), findsNothing);
      // Back to the top, where the header recounts the set.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text(_en.picksIntroCount(2)), findsOneWidget);
    });

    testWidgets('Discover More stays one tap away', (tester) async {
      await pumpView(tester);
      await tester.scrollUntilVisible(
        find.text(_en.picksDiscoverMoreHint),
        300,
      );
      await tester.tap(find.text(_en.picksDiscoverMoreHint));
      expect(discoverMoreTaps, 1);
    });

    testWidgets('low supply says so instead of padding the list', (
      tester,
    ) async {
      repository.batch = batchOf([pickPayload(uid: 'a')], status: 'lowSupply');
      await pumpView(tester);
      expect(find.text(_en.picksLowSupplyNote(1)), findsOneWidget);
    });

    testWidgets('an empty batch shows the deliberate preparing state', (
      tester,
    ) async {
      repository.batch = batchOf(
        const [],
        status: 'empty',
        emptyReason: 'noCandidates',
      );
      await pumpView(tester);
      expect(find.text(_en.picksEmptyPreparingTitle), findsOneWidget);
      expect(find.text(_en.picksEmptyPreparingMessage), findsOneWidget);
      await tester.tap(find.text(_en.picksDiscoverMore));
      expect(discoverMoreTaps, 1);
    });

    testWidgets('long names and large text do not overflow on a small phone', (
      tester,
    ) async {
      repository.batch = batchOf([
        pickPayload(
          uid: 'long',
          name: 'Anastasia Konstantinopoulou-Yıldırımoğlu',
          age: 34,
          pickType: 'unexpectedMatch',
          labels: const ['unexpectedMatch', 'valuesMatch', 'bestOverall'],
          overall: 81,
        ),
      ]);
      await pumpView(tester, textScale: 1.4, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Anastasia'), findsOneWidget);
    });
  });

  group('Discover tab modes', () {
    testWidgets(
      'opens on Picks; Discover More is a mode with its own way back',
      (tester) async {
        final discovery = DiscoveryController(
          uid: 'viewer',
          locationRepository: FakeLocationRepository(
            permission: LocationPermissionStatus.granted,
          ),
          discoveryRepository: InMemoryDiscoveryRepository(
            seeds: const [
              DiscoverySeed(
                profile: UserProfile(uid: 'ada', displayName: 'Ada', age: 27),
                distanceKm: 3,
                distanceLabel: '3 km away',
              ),
            ],
          ),
          loadDeckOnStart: false,
        );
        final picks = MevoraPicksController(
          repository: FakeMevoraPicksRepository(batchOf(_mixedBatch())),
          removalDuration: Duration.zero,
        );
        addTearDown(discovery.dispose);
        addTearDown(picks.dispose);

        await tester.pumpWidget(
          _app(DiscoveryPage(controller: discovery, picksController: picks)),
        );
        await tester.pumpAndSettle();

        expect(find.text(_en.picksTitle), findsOneWidget);
        expect(find.text('Zeynep, 25'), findsOneWidget);
        // The deck has not been fetched behind Picks.
        expect(discovery.state.candidates, isEmpty);

        await tester.scrollUntilVisible(
          find.text(_en.picksDiscoverMoreHint),
          300,
        );
        await tester.tap(find.text(_en.picksDiscoverMoreHint));
        await tester.pumpAndSettle();
        expect(find.text(_en.discoverMoreSubtitle), findsOneWidget);
        expect(find.text('Ada, 27'), findsOneWidget);

        await tester.tap(find.byTooltip(_en.picksBackToPicks));
        await tester.pumpAndSettle();
        expect(find.text(_en.picksTitle), findsOneWidget);
        expect(find.text('Zeynep, 25'), findsOneWidget);
      },
    );

    testWidgets(
      'profile open and back keeps the Pick; Like from the profile decides',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final discovery = DiscoveryController(
          uid: 'viewer',
          locationRepository: FakeLocationRepository(
            permission: LocationPermissionStatus.granted,
          ),
          discoveryRepository: InMemoryDiscoveryRepository(),
          loadDeckOnStart: false,
        );
        final repository = FakeMevoraPicksRepository(batchOf(_mixedBatch()));
        final picks = MevoraPicksController(
          repository: repository,
          removalDuration: Duration.zero,
        );
        addTearDown(discovery.dispose);
        addTearDown(picks.dispose);

        await tester.pumpWidget(
          _app(DiscoveryPage(controller: discovery, picksController: picks)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Zeynep, 25'));
        await tester.pumpAndSettle();
        expect(find.byType(DiscoveryProfileDetailsPage), findsOneWidget);
        expect(find.text(_en.pickWhyTitle('Zeynep')), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Zeynep, 25'), findsOneWidget);
        expect(repository.decisions, isEmpty);
        expect(picks.state.picks.map((p) => p.uid), contains('zeynep'));

        await tester.tap(find.text('Zeynep, 25'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsLabel(_en.picksLikeSemantics('Zeynep')).last,
        );
        await tester.pumpAndSettle();
        expect(repository.decisions, [('zeynep', DiscoveryDecision.like)]);
        expect(find.byType(DiscoveryProfileDetailsPage), findsNothing);
        expect(picks.state.picks.any((p) => p.uid == 'zeynep'), isFalse);
        expect(picks.state.picks.first.pickType, PickType.unexpectedMatch);
      },
    );
  });
}
