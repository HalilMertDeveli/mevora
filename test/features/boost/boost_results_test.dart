import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_results.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_results_panel.dart';
import 'package:mevora/features/discovery/domain/services/discovery_boost_ranking.dart';
import 'package:mevora/l10n/app_localizations.dart';

Boost buildBoost({
  required BoostStatus status,
  required DateTime expiresAt,
  BoostResults results = BoostResults.empty,
}) {
  return Boost(
    boostId: 'b1',
    userId: 'u1',
    productId: 'p1',
    purchaseId: 'pur1',
    status: status,
    createdAt: DateTime.utc(2026, 9, 22, 11),
    startedAt: DateTime.utc(2026, 9, 22, 11, 30),
    expiresAt: expiresAt,
    results: results,
  );
}

Future<void> pumpPanel(
  WidgetTester tester,
  Boost? boost, {
  required DateTime now,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: BoostResultsPanel(boost: boost, now: now)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime.utc(2026, 9, 22, 12);
  final future = DateTime.utc(2026, 9, 22, 13);
  final past = DateTime.utc(2026, 9, 22, 11, 45);

  group('21. active Boost results', () {
    testWidgets('shows counted metrics while running', (tester) async {
      await pumpPanel(
        tester,
        buildBoost(
          status: BoostStatus.active,
          expiresAt: future,
          results: const BoostResults(
            totalImpressions: 40,
            uniqueUsersReached: 32,
            likesReceived: 5,
            matchesCreated: 1,
          ),
        ),
        now: now,
      );
      expect(find.textContaining('32'), findsOneWidget);
      expect(find.textContaining('5 likes'), findsOneWidget);
      expect(find.textContaining('1 match'), findsOneWidget);
    });

    testWidgets('says counting rather than showing premature zeroes', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        buildBoost(status: BoostStatus.active, expiresAt: future),
        now: now,
      );
      expect(find.textContaining('Counting'), findsOneWidget);
      expect(find.textContaining('0 likes'), findsNothing);
    });
  });

  group('22/23. completed Boost results', () {
    testWidgets('shows the final metrics', (tester) async {
      await pumpPanel(
        tester,
        buildBoost(
          status: BoostStatus.expired,
          expiresAt: past,
          results: const BoostResults(
            totalImpressions: 80,
            uniqueUsersReached: 68,
            likesReceived: 12,
            matchesCreated: 4,
          ),
        ),
        now: now,
      );
      expect(find.textContaining('Boost finished'), findsOneWidget);
      expect(find.textContaining('68'), findsOneWidget);
      expect(find.textContaining('12 likes'), findsOneWidget);
      expect(find.textContaining('4 matches'), findsOneWidget);
    });

    testWidgets('23. a zero-result Boost stays truthful', (tester) async {
      await pumpPanel(
        tester,
        buildBoost(status: BoostStatus.expired, expiresAt: past),
        now: now,
      );
      expect(find.textContaining('did not reach anyone'), findsOneWidget);
      // No invented success wording, no comparison percentage.
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('zero likes and matches render as real zeroes', (tester) async {
      await pumpPanel(
        tester,
        buildBoost(
          status: BoostStatus.expired,
          expiresAt: past,
          results: const BoostResults(
            totalImpressions: 9,
            uniqueUsersReached: 9,
          ),
        ),
        now: now,
      );
      expect(find.textContaining('0 likes'), findsOneWidget);
      expect(find.textContaining('0 matches'), findsOneWidget);
    });
  });

  group('24/25. missing data', () {
    testWidgets('24. no Boost renders nothing rather than failing', (
      tester,
    ) async {
      await pumpPanel(tester, null, now: now);
      expect(find.byType(BoostResultsPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('BoostResults value object', () {
    test('empty means nothing counted yet', () {
      expect(BoostResults.empty.isEmpty, isTrue);
      expect(BoostResults.empty.hasAnyOutcome, isFalse);
    });

    test('reach without outcome is still not empty', () {
      const results = BoostResults(totalImpressions: 3, uniqueUsersReached: 3);
      expect(results.isEmpty, isFalse);
      expect(results.hasAnyOutcome, isFalse);
    });
  });

  group('26/27. demo ranking parity with production', () {
    const radius = 25;

    List<Map<String, Object>> demoOrder(
      List<Map<String, Object>> items,
      Set<String> boosted,
    ) {
      return DiscoveryBoostRanking.sortCandidates<Map<String, Object>>(
        items: items,
        boostedUids: boosted,
        radiusKm: radius,
        uidOf: (i) => i['uid']! as String,
        compatibilityOf: (i) => i['compat']! as int,
        musicBonusOf: (_) => 0,
        distanceOf: (i) => (i['dist']! as num).toDouble(),
      );
    }

    Map<String, Object> c(String uid, int compat, double dist) => {
      'uid': uid,
      'compat': compat,
      'dist': dist,
    };

    test('26. no forced B/N interleave: a weak boosted profile stays back', () {
      final result = demoOrder(
        [c('normal_95', 95, 5), c('normal_90', 90, 5), c('boost_10', 10, 5)],
        {'boost_10'},
      );
      expect(result.map((i) => i['uid']), ['normal_95', 'normal_90', 'boost_10']);
    });

    test('a boosted profile inside the bonus band does rank ahead', () {
      final result = demoOrder(
        [c('normal', 72, 5), c('boosted', 70, 5)],
        {'boosted'},
      );
      expect(result.first['uid'], 'boosted');
    });

    test('a compatibility gap wider than the bonus still wins', () {
      final result = demoOrder(
        [c('normal', 95, 5), c('boosted', 50, 5)],
        {'boosted'},
      );
      expect(result.first['uid'], 'normal');
    });

    test('27. demo never alters the compatibility value', () {
      final items = [c('boosted', 70, 5), c('normal', 72, 5)];
      demoOrder(items, {'boosted'});
      expect(items.firstWhere((i) => i['uid'] == 'boosted')['compat'], 70);
      expect(items.firstWhere((i) => i['uid'] == 'normal')['compat'], 72);
    });

    test('demo honours the same compatibility floor as the server', () {
      expect(DiscoveryBoostRanking.minCompatibility, 45);
      expect(DiscoveryBoostRanking.boostPriorityBonus, 35);
      expect(
        DiscoveryBoostRanking.boostAdvantageApplies(
          uid: 'a',
          compatibilityScore: 44,
          boostedUids: {'a'},
        ),
        isFalse,
      );
    });
  });
}
