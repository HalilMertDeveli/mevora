import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_daily_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_daily_page.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_daily_entry_card.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_lab_discover_entry.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/fake_network_images.dart';
import '../../helpers/l10n_harness.dart';

class _RecordingAnalytics implements AnalyticsProvider {
  final List<(String, Map<String, Object>?)> events = [];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name, parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

class _UnusedPurchases implements PurchaseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Items in a day, as the server serves them.
const _daySize = MockHumorDataSource.dailySetSize;

/// The first item of the day after calibration, in [_textSeed].
const _firstOfDay = MockHumorDataSource.onboardingCount;

/// A text-only sequence — the calibration items and one day after them — so
/// no media player is involved.
final _textSeed = <HumorContent>[
  for (var i = 0; i < _firstOfDay + _daySize; i += 1)
    HumorContent(
      contentId: 'txt_$i',
      type: HumorContentType.text,
      language: 'tr',
      category: HumorCategory.values[i % HumorCategory.values.length],
      textBody: 'Metin $i',
    ),
];

/// A user who finished calibration on an earlier day, so a day is served.
MockHumorDataSource _calibratedSource({List<HumorContent>? seed}) =>
    MockHumorDataSource(seed: seed)..completeCalibration();

HumorDailySet _set({int answered = 0, int total = _daySize}) => HumorDailySet(
  status: HumorDailyStatus.ready,
  dayId: '2026-09-29',
  total: total,
  answeredCount: answered,
  completed: answered >= total,
  nextIndex: answered,
  items: _textSeed.take(total).toList(),
);

Widget _app(
  Widget home, {
  MockHumorDataSource? source,
  AnalyticsProvider? analytics,
}) {
  Widget app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('tr'),
    home: Scaffold(body: home),
  );
  if (analytics != null) {
    app = BoostScope(
      repository: _UnusedPurchases(),
      analytics: analytics,
      child: app,
    );
  }
  if (source != null) {
    app = HumorScope(
      repository: HumorRepositoryImpl(dataSource: source),
      child: app,
    );
  }
  return AppScope(
    config: const AppConfig(
      environment: AppEnvironment.development,
      featureFlags: FeatureFlags(humorLabEnabled: true),
    ),
    logger: const AppLogger(environment: AppEnvironment.development),
    child: app,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _categoryLabels(AppLocalizations l10n) => [
  l10n.humorCategorySarcasm,
  l10n.humorCategoryAbsurd,
  l10n.humorCategorySilly,
  l10n.humorCategoryRomantic,
  l10n.humorCategoryDark,
  l10n.humorCategoryMeme,
  l10n.humorCategoryDry,
  l10n.humorCategoryWordplay,
  l10n.humorCategorySituational,
  l10n.humorCategoryCringe,
  l10n.humorCategoryTeasing,
];

void main() {
  final l10n = l10nTr();

  setUp(HumorDailyDeferral.reset);

  group('entry card', () {
    testWidgets('a fresh day offers "Başla" and "Sonra"', (tester) async {
      await tester.pumpWidget(
        _app(HumorDailyEntryCard(set: _set(), onStart: () {}, onDefer: () {})),
      );

      expect(find.text('Bugünün Mizah Turu 🎭'), findsOneWidget);
      expect(find.text(l10n.humorDailyBody), findsOneWidget);
      expect(find.text(l10n.humorDailySecondary), findsOneWidget);
      expect(find.text('5 kısa video'), findsOneWidget);
      expect(find.textContaining('10'), findsNothing);
      expect(find.text('Başla'), findsOneWidget);
      expect(find.text('Sonra'), findsOneWidget);
    });

    testWidgets('a started day offers "Devam et · 2/5"', (tester) async {
      await tester.pumpWidget(
        _app(
          HumorDailyEntryCard(
            set: _set(answered: 2),
            onStart: () {},
            onDefer: () {},
          ),
        ),
      );

      expect(find.text('Devam et · 2/5'), findsOneWidget);
      expect(find.text('Başla'), findsNothing);
    });

    testWidgets('a finished day is quiet and cannot be reopened', (
      tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(
        _app(
          HumorDailyEntryCard(
            set: _set(answered: _daySize),
            onStart: () => started += 1,
          ),
        ),
      );

      expect(find.text('Bugünlük tamam ✓'), findsOneWidget);
      expect(find.byType(MevoraButton), findsNothing);
      await tester.tap(find.text('Bugünlük tamam ✓'));
      expect(started, 0);
    });

    testWidgets('starts tomorrow: one quiet line, never a CTA', (tester) async {
      await tester.pumpWidget(
        _app(
          const HumorDailyEntryCard(
            set: HumorDailySet(
              status: HumorDailyStatus.locked,
              lockedReason: HumorDailyLockedReason.startsTomorrow,
            ),
          ),
        ),
      );

      expect(find.text(l10n.humorDailyStartsTomorrow), findsOneWidget);
      expect(find.byType(MevoraButton), findsNothing);
      expect(find.text(l10n.humorDailyTitle), findsNothing);
    });

    testWidgets('not ready or calibrating: nothing at all', (tester) async {
      for (final set in const [
        HumorDailySet.notReady,
        HumorDailySet(
          status: HumorDailyStatus.locked,
          lockedReason: HumorDailyLockedReason.calibrationIncomplete,
        ),
      ]) {
        await tester.pumpWidget(_app(HumorDailyEntryCard(set: set)));
        expect(find.text(l10n.humorDailyTitle), findsNothing);
        expect(find.byType(MevoraButton), findsNothing);
      }
    });
  });

  group('discover entry', () {
    testWidgets('shows the daily card once calibrated; "Sonra" hides it', (
      tester,
    ) async {
      final source = _calibratedSource();
      final analytics = _RecordingAnalytics();
      await tester.pumpWidget(
        _app(
          const HumorLabDiscoverEntry(),
          source: source,
          analytics: analytics,
        ),
      );
      await _settle(tester);

      expect(find.text(l10n.humorDailyTitle), findsOneWidget);
      expect(find.text(l10n.humorDailyStart), findsOneWidget);
      // The other card is the humor profile now — there is no feed to open.
      expect(find.text(l10n.humorProfileTitle), findsOneWidget);
      expect(find.text(l10n.humorLabDiscoverCta), findsNothing);
      expect(analytics.events, hasLength(1));
      expect(analytics.events.single.$1, AnalyticsEvents.dailyHumorImpression);
      expect(analytics.events.single.$2, {'answered': 0, 'total': _daySize});

      await tester.tap(find.text(l10n.humorDailyLater));
      await _settle(tester);

      expect(find.text(l10n.humorDailyTitle), findsNothing);
      expect(find.text(l10n.humorProfileTitle), findsOneWidget);
      expect(analytics.events.last.$1, AnalyticsEvents.dailyHumorDeferred);
      expect(analytics.events.last.$2, {'answered': 0});
      expect(analytics.events, hasLength(2), reason: 'impression only once');
      expect(source.dailyAnswers, isEmpty, reason: 'no server state changes');
      expect(source.dailySubmitCalls + source.dailySkipCalls, 0);
    });

    testWidgets('no daily card while calibration is incomplete', (
      tester,
    ) async {
      final source = MockHumorDataSource();
      await tester.pumpWidget(
        _app(const HumorLabDiscoverEntry(), source: source),
      );
      await _settle(tester);

      expect(find.text(l10n.humorDailyTitle), findsNothing);
      expect(source.dailySetCalls, 0);
    });

    testWidgets('no card and no CTA when the tour starts tomorrow', (
      tester,
    ) async {
      final source = _calibratedSource();
      source.dailyStartsTomorrow = true;
      await tester.pumpWidget(
        _app(const HumorLabDiscoverEntry(), source: source),
      );
      await _settle(tester);

      expect(find.text(l10n.humorDailyTitle), findsNothing);
      expect(find.text(l10n.humorDailyStart), findsNothing);
      expect(find.text(l10n.humorDailyStartsTomorrow), findsOneWidget);
    });
  });

  group('tour page', () {
    testWidgets('plays in order with progress and never names a category', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = _calibratedSource(seed: _textSeed);
        final controller = HumorDailyController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _app(HumorDailyPage(controller: controller), source: source),
        );
        await _settle(tester);

        expect(find.text('1/5'), findsOneWidget);
        expect(find.text(l10n.humorDailyHintStart), findsOneWidget);
        // The day starts where the calibration ended.
        expect(find.text('Metin $_firstOfDay'), findsOneWidget);
        // No skip: an item is a measurement.
        for (final label in ['Geç', 'Skip']) {
          expect(find.text(label), findsNothing);
        }
        expect(find.textContaining('/10'), findsNothing);
        for (final label in _categoryLabels(l10n)) {
          expect(find.text(label), findsNothing, reason: label);
        }

        await tester.tap(
          find.descendant(
            of: find.byType(HumorRatingBar),
            matching: find.text(l10n.humorRatingFunny),
          ),
        );
        await _settle(tester);

        expect(find.text('2/5'), findsOneWidget);
        expect(find.text(l10n.humorDailyHintMiddle), findsOneWidget);
        expect(find.text('Metin ${_firstOfDay + 1}'), findsOneWidget);
        for (final label in _categoryLabels(l10n)) {
          expect(find.text(label), findsNothing, reason: label);
        }
      });
    });

    testWidgets('resumes mid-tour and finishes on the completion screen', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = _calibratedSource(seed: _textSeed);
        source.seedDailyProgress(_daySize - 1);
        final controller = HumorDailyController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _app(HumorDailyPage(controller: controller), source: source),
        );
        await _settle(tester);

        expect(find.text('5/5'), findsOneWidget);
        expect(find.text(l10n.humorDailyHintEnd), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(HumorRatingBar),
            matching: find.text(l10n.humorRatingNeutral),
          ),
        );
        await _settle(tester);

        expect(find.text('Bugünlük tamam 🎭'), findsOneWidget);
        expect(
          find.text(
            '${l10n.humorDailyCompletedBody} '
            '${l10n.humorDailyCompletedTomorrow}',
          ),
          findsOneWidget,
        );
        expect(find.byType(HumorRatingBar), findsNothing);
        // The only way on is out: nothing offers tomorrow's items today.
        expect(find.byType(MevoraButton), findsOneWidget);
        expect(find.text(l10n.close), findsOneWidget);
        expect(find.text(l10n.humorDailyStart), findsNothing);
        expect(source.dailyAnswers, hasLength(_daySize));
      });
    });

    testWidgets('a member who is through the whole sequence is told so', (
      tester,
    ) async {
      // Nothing after the calibration items: the sequence ends there.
      final source = _calibratedSource(
        seed: _textSeed.take(_firstOfDay).toList(),
      );
      final controller = HumorDailyController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await tester.pumpWidget(
        _app(HumorDailyPage(controller: controller), source: source),
      );
      await _settle(tester);

      expect(find.text(l10n.humorDailySequenceComplete), findsOneWidget);
      expect(find.byType(HumorRatingBar), findsNothing);
      expect(find.text(l10n.humorDailyNotReadyTitle), findsNothing);
    });

    testWidgets('the day after calibration says the tour starts tomorrow', (
      tester,
    ) async {
      final source = MockHumorDataSource(seed: _textSeed);
      for (final contentId in source.sequenceIds.take(_firstOfDay)) {
        await source.submitFeedback(
          contentId: contentId,
          rating: HumorRating.funny,
        );
      }
      final controller = HumorDailyController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await tester.pumpWidget(
        _app(HumorDailyPage(controller: controller), source: source),
      );
      await _settle(tester);

      expect(find.text(l10n.humorDailyStartsTomorrow), findsOneWidget);
      expect(find.byType(HumorRatingBar), findsNothing);
      expect(find.textContaining('Metin'), findsNothing);
    });

    testWidgets('not ready is calm, with no filler content', (tester) async {
      final source = _calibratedSource(seed: _textSeed);
      source.dailyNotReady = true;
      final controller = HumorDailyController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await tester.pumpWidget(
        _app(HumorDailyPage(controller: controller), source: source),
      );
      await _settle(tester);

      expect(find.text(l10n.humorDailyNotReadyTitle), findsOneWidget);
      expect(find.byType(HumorRatingBar), findsNothing);
      expect(find.textContaining('Metin'), findsNothing);
    });
  });
}
