import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_calibration_intro_page.dart';
import 'package:mevora/features/humor/presentation/pages/humor_calibration_result_page.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_lab_discover_entry.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_profile_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_rating_bar.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_network_images.dart';
import '../../helpers/l10n_harness.dart';

const _discoveryMarker = 'discovery-screen';
const _dailyMarker = 'daily-screen';

/// How many items the initial calibration has on the mock server.
const _total = MockHumorDataSource.onboardingCount;

GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.discovery,
        builder: (_, _) => const Scaffold(body: Text(_discoveryMarker)),
      ),
      GoRoute(
        path: AppRoutes.humorCalibration,
        builder: (_, _) => const HumorCalibrationIntroPage(),
      ),
      GoRoute(
        path: AppRoutes.humorLab,
        builder: (_, _) => const HumorLabPage(),
      ),
      GoRoute(
        path: AppRoutes.humorResult,
        builder: (_, _) => const HumorCalibrationResultPage(),
      ),
      GoRoute(
        path: AppRoutes.humorDaily,
        builder: (_, _) => const Scaffold(body: Text(_dailyMarker)),
      ),
    ],
  );
}

Widget _routerApp(GoRouter router, MockHumorDataSource source) {
  return HumorScope(
    repository: HumorRepositoryImpl(dataSource: source),
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
    ),
  );
}

Widget _plainApp(Widget home, {MockHumorDataSource? source}) {
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('tr'),
    home: home,
  );
  if (source == null) {
    return app;
  }
  return HumorScope(
    repository: HumorRepositoryImpl(dataSource: source),
    child: app,
  );
}

/// Rate the first [count] items of the sequence directly on the backend, as
/// another session earlier today.
Future<void> _preRate(MockHumorDataSource source, int count) async {
  for (final contentId in source.sequenceIds.take(count)) {
    await source.submitFeedback(
      contentId: contentId,
      rating: HumorRating.funny,
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  // Media and loaders animate forever, so settle by time, not by idleness.
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _ratingChip(String label) => find.descendant(
  of: find.byType(HumorRatingBar),
  matching: find.text(label),
);

/// The rating controls stay laid out at the end of the feed (so the card
/// area never resizes) but must not be visible or usable there.
bool _ratingControlsVisible(WidgetTester tester) {
  final visibility = tester.widget<Visibility>(
    find
        .ancestor(
          of: find.byType(HumorRatingBar),
          matching: find.byType(Visibility),
        )
        .first,
  );
  return visibility.visible;
}

void main() {
  final l10n = l10nTr();

  group('navigation', () {
    testWidgets('a calibrated user opening the Lab finds no feed, and is '
        'pointed at the daily tour', (tester) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource()..completeCalibration();
        final router = _router(AppRoutes.discovery);
        await tester.pumpWidget(_routerApp(router, source));
        await _settle(tester);

        unawaited(router.push<void>(AppRoutes.humorLab));
        await _settle(tester);

        expect(find.byType(HumorLabPage), findsOneWidget);
        expect(find.byType(HumorCalibrationResultPage), findsNothing);
        // Nothing to rate here: the next items come with the daily tour.
        expect(find.byType(HumorRatingBar), findsNothing);
        expect(find.text(l10n.humorLabCalibratedBody), findsOneWidget);
        expect(source.profile.interactionCount, _total);

        await tester.tap(find.text(l10n.humorDailyTitle));
        await _settle(tester);

        expect(find.text(_dailyMarker), findsOneWidget);
        expect(find.byType(HumorLabPage), findsNothing);
        expect(source.profile.interactionCount, _total);
      });
    });

    testWidgets('intro Start pushes the Lab, and closing it returns', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        final router = _router(AppRoutes.discovery);
        await tester.pumpWidget(_routerApp(router, source));
        await _settle(tester);
        unawaited(router.push<void>(AppRoutes.humorCalibration));
        await _settle(tester);

        await tester.tap(find.text(l10n.humorCalibrationStart));
        await _settle(tester);
        expect(find.byType(HumorLabPage), findsOneWidget);

        await tester.tap(_ratingChip(l10n.humorRatingFunny));
        await _settle(tester);

        await tester.tap(find.byType(BackButtonIcon));
        await _settle(tester);

        expect(find.byType(HumorLabPage), findsNothing);
        expect(find.byType(HumorCalibrationIntroPage), findsOneWidget);
        // Back on the invitation, which now knows about the progress made.
        expect(find.text(l10n.humorCalibrationResume), findsOneWidget);
        expect(
          find.text(l10n.humorCalibrationProgress(1, _total)),
          findsOneWidget,
        );

        // Skipping from a pushed invitation goes back where it came from.
        await tester.tap(find.text(l10n.humorCalibrationSkip).last);
        await _settle(tester);
        expect(find.text(_discoveryMarker), findsOneWidget);
      });
    });

    testWidgets('a Lab opened as the only screen can still be closed', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        final router = _router(AppRoutes.humorLab);
        await tester.pumpWidget(_routerApp(router, source));
        await _settle(tester);

        await tester.tap(find.byIcon(MevoraIcons.close));
        await _settle(tester);

        expect(find.byType(HumorLabPage), findsNothing);
        expect(find.text(_discoveryMarker), findsOneWidget);
      });
    });

    testWidgets('the last rating hands off to the result screen', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        await _preRate(source, _total - 1);
        final router = _router(AppRoutes.discovery);
        await tester.pumpWidget(_routerApp(router, source));
        await _settle(tester);
        unawaited(router.push<void>(AppRoutes.humorLab));
        await _settle(tester);
        expect(
          find.text(l10n.humorCalibrationProgress(_total - 1, _total)),
          findsOneWidget,
        );

        await tester.tap(_ratingChip(l10n.humorRatingVeryFunny));
        await _settle(tester);

        expect(find.byType(HumorCalibrationResultPage), findsOneWidget);
        expect(find.byType(HumorLabPage), findsNothing);
        expect(find.text(l10n.humorResultTitle), findsOneWidget);
      });
    });
  });

  group('discover entry', () {
    Widget entryApp(GoRouter router, MockHumorDataSource source) {
      return AppScope(
        config: const AppConfig(
          environment: AppEnvironment.development,
          featureFlags: FeatureFlags(humorLabEnabled: true),
        ),
        logger: const AppLogger(environment: AppEnvironment.development),
        child: _routerApp(router, source),
      );
    }

    GoRouter entryRouter() {
      return GoRouter(
        initialLocation: AppRoutes.discovery,
        routes: [
          GoRoute(
            path: AppRoutes.discovery,
            builder: (_, _) => const Scaffold(body: HumorLabDiscoverEntry()),
          ),
          GoRoute(
            path: AppRoutes.humorCalibration,
            builder: (_, _) => const Scaffold(body: Text('intro')),
          ),
          GoRoute(
            path: AppRoutes.humorLab,
            builder: (_, _) => const Scaffold(body: Text('lab')),
          ),
          GoRoute(
            path: AppRoutes.humorResult,
            builder: (_, _) => const Scaffold(body: Text('profile')),
          ),
        ],
      );
    }

    testWidgets('routes through the invitation until calibration is done', (
      tester,
    ) async {
      final source = MockHumorDataSource();
      await _preRate(source, 4);
      await tester.pumpWidget(entryApp(entryRouter(), source));
      await _settle(tester);

      expect(
        find.text(l10n.humorProfileEntryInProgress(4, _total)),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.humorLabDiscoverCta));
      await _settle(tester);
      expect(find.text('intro'), findsOneWidget);
    });

    testWidgets('opens the humor profile once calibration is done — never '
        'an open-ended feed', (tester) async {
      final source = MockHumorDataSource()..completeCalibration();
      await tester.pumpWidget(entryApp(entryRouter(), source));
      await _settle(tester);

      expect(find.text(l10n.humorLabDiscoverCta), findsNothing);
      expect(find.text(l10n.humorProfileEntryComplete), findsOneWidget);
      await tester.tap(find.text(l10n.humorProfileTitle));
      await _settle(tester);
      expect(find.text('profile'), findsOneWidget);
      expect(find.text('lab'), findsNothing);
    });
  });

  group('lab session', () {
    testWidgets('a failed rating is reported with a retry that advances once', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource()..failFeedback = true;
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _plainApp(HumorLabPage(controller: controller), source: source),
        );
        await _settle(tester);

        await tester.tap(_ratingChip(l10n.humorRatingFunny));
        await _settle(tester);

        expect(find.byType(SnackBar), findsOneWidget);
        expect(controller.state.currentIndex, 0);
        expect(
          find.text(l10n.humorCalibrationProgress(0, _total)),
          findsOneWidget,
        );

        source.failFeedback = false;
        await tester.tap(find.byType(SnackBarAction));
        await _settle(tester);

        expect(controller.state.currentIndex, 1);
        expect(source.profile.interactionCount, 1);
        expect(
          find.text(l10n.humorCalibrationProgress(1, _total)),
          findsOneWidget,
        );
      });
    });

    testWidgets('there is no skip and no save button: every item is a '
        'measurement', (tester) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _plainApp(HumorLabPage(controller: controller), source: source),
        );
        await _settle(tester);

        expect(find.byType(HumorRatingBar), findsOneWidget);
        expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
        expect(find.byIcon(MevoraIcons.skip), findsNothing);
        for (final label in ['Geç', 'Skip']) {
          expect(find.text(label), findsNothing);
        }
        expect(source.skipCalls, 0);
      });
    });

    testWidgets('finishing shows the end instead of a rated card, with '
        'nothing more to rate', (tester) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        await _preRate(source, _total - 1);
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _plainApp(HumorLabPage(controller: controller), source: source),
        );
        await _settle(tester);
        expect(controller.state.items, hasLength(1));

        await tester.tap(_ratingChip(l10n.humorRatingFunny));
        await _settle(tester);

        expect(controller.state.reachedEnd, isTrue);
        expect(find.text(l10n.humorLabCalibratedBody), findsOneWidget);
        expect(_ratingControlsVisible(tester), isFalse);
        // No retry, no "more": the next items are tomorrow's.
        expect(find.text(l10n.humorTryAgain), findsNothing);
        expect(source.profile.interactionCount, _total);
      });
    });

    testWidgets('rating through several items lands on the end page', (
      tester,
    ) async {
      // Regression: hiding the rating controls used to grow the pager while
      // it was still animating to the end slot, so it stopped short and left
      // an already-rated card on screen with no controls and no explanation.
      await withFakeNetworkImages(() async {
        const remaining = 5;
        final source = MockHumorDataSource();
        await _preRate(source, _total - remaining);
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _plainApp(HumorLabPage(controller: controller), source: source),
        );
        await _settle(tester);
        expect(controller.state.items, hasLength(remaining));

        for (var i = 0; i < remaining; i += 1) {
          await tester.tap(_ratingChip(l10n.humorRatingFunny));
          await _settle(tester);
        }

        expect(controller.state.reachedEnd, isTrue);
        expect(find.text(l10n.humorLabCalibratedBody), findsOneWidget);
        expect(_ratingControlsVisible(tester), isFalse);
      });
    });

    testWidgets('a calibration paused by media that would not play says it '
        'continues tomorrow', (tester) async {
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource(
          seed: MockHumorDataSource.seedCatalog.take(2).toList(),
        );
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        await tester.pumpWidget(
          _plainApp(HumorLabPage(controller: controller), source: source),
        );
        await _settle(tester);

        await controller.skipUnplayable(controller.state.current!.contentId);
        await _settle(tester);
        await tester.tap(_ratingChip(l10n.humorRatingFunny));
        await _settle(tester);

        expect(controller.state.continuesTomorrow, isTrue);
        expect(find.text(l10n.humorCalibrationPausedTitle), findsOneWidget);
        expect(find.text(l10n.humorCalibrationPausedBody), findsOneWidget);
        // Not "all done", and not something to retry.
        expect(find.text(l10n.humorLabCalibratedBody), findsNothing);
        expect(find.text(l10n.humorFeedAllCaughtUp), findsNothing);
        expect(find.text(l10n.humorTryAgain), findsNothing);
        expect(source.profile.interactionCount, 1);
      });
    });
  });

  group('result screen', () {
    testWidgets('a failed load is an error with a retry, not a ready profile', (
      tester,
    ) async {
      final source = MockHumorDataSource(
        profile: const UserHumorProfile(
          vector: {HumorCategory.sarcasm: 86},
          interactionCount: 15,
          profileBuilding: false,
        ),
      )..failProfile = true;
      await tester.pumpWidget(
        _plainApp(const HumorCalibrationResultPage(), source: source),
      );
      await _settle(tester);

      expect(find.text(l10n.humorResultTitle), findsNothing);
      expect(find.text(l10n.humorTryAgain), findsOneWidget);
      expect(find.text(l10n.humorResultDone), findsOneWidget);

      source.failProfile = false;
      await tester.tap(find.text(l10n.humorTryAgain));
      await _settle(tester);

      expect(find.text(l10n.humorResultTitle), findsOneWidget);
      expect(find.text(l10n.humorCategorySarcasm), findsOneWidget);
    });

    testWidgets('without a humor backend it offers a way on, not a spinner', (
      tester,
    ) async {
      var done = false;
      await tester.pumpWidget(
        _plainApp(HumorCalibrationResultPage(onDone: () => done = true)),
      );
      await _settle(tester);

      expect(find.text(l10n.humorResultTitle), findsNothing);
      await tester.tap(find.text(l10n.humorResultDone));
      await tester.pump();
      expect(done, isTrue);
    });

    testWidgets('trait bars announce strength words, never raw values', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final source = MockHumorDataSource(
        profile: const UserHumorProfile(
          vector: {HumorCategory.sarcasm: 86, HumorCategory.dry: 71},
          interactionCount: 15,
          profileBuilding: false,
        ),
      );
      await tester.pumpWidget(
        _plainApp(const HumorCalibrationResultPage(), source: source),
      );
      await _settle(tester);
      expect(find.text(l10n.humorCategorySarcasm), findsOneWidget);

      final announced = <String>[];
      void visit(SemanticsNode node) {
        announced
          ..add(node.label)
          ..add(node.value);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.getSemantics(find.byType(HumorCalibrationResultPage)));
      expect(announced, contains(l10n.humorResultStrengthHigh));
      expect(announced.where((text) => RegExp(r'\d').hasMatch(text)), isEmpty);
      semantics.dispose();
    });
  });

  group('profile sheet', () {
    testWidgets('shows strength words for real traits and no raw numbers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _plainApp(
          const Scaffold(
            body: HumorProfileSheet(
              profile: UserHumorProfile(
                vector: {
                  HumorCategory.sarcasm: 88,
                  HumorCategory.absurd: 67,
                  HumorCategory.dry: 52,
                },
                interactionCount: 18,
                profileBuilding: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          '${l10n.humorCategorySarcasm} · ${l10n.humorResultStrengthHigh}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${l10n.humorCategoryAbsurd} · ${l10n.humorResultStrengthMedium}',
        ),
        findsOneWidget,
      );
      // Near-neutral is no evidence, not a trait.
      expect(find.textContaining(l10n.humorCategoryDry), findsNothing);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });

    testWidgets('says so when nothing stands out yet', (tester) async {
      await tester.pumpWidget(
        _plainApp(
          const Scaffold(
            body: HumorProfileSheet(
              profile: UserHumorProfile(
                vector: {HumorCategory.meme: 54, HumorCategory.dark: 47},
                interactionCount: 15,
                profileBuilding: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.humorResultSummaryNone), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });
  });
}
