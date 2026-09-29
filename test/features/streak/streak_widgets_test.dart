import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/streak_scope.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/streak/data/streak_analytics.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';
import 'package:mevora/features/streak/presentation/widgets/streak_celebration.dart';
import 'package:mevora/features/streak/presentation/widgets/streak_details_sheet.dart';
import 'package:mevora/features/streak/presentation/widgets/streak_indicator.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'streak_fixtures.dart';

void main() {
  late ScriptedStreakRepository repository;
  late RecordingAnalytics analytics;
  late DailyStreakController controller;

  setUp(() {
    repository = ScriptedStreakRepository();
    analytics = RecordingAnalytics();
    controller = DailyStreakController(
      repository: repository,
      analytics: StreakAnalytics(analytics),
      clock: () => DateTime(2026, 9, 29, 15),
      retryDelays: const [],
    );
  });

  tearDown(() => controller.dispose());

  Widget app(
    Widget child, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    bool disableAnimations = false,
  }) {
    return StreakScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: inner!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Picks'), actions: [child]),
          body: const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<void> signIn(WidgetTester tester, DailyCheckInResult result) async {
    repository.enqueue(result);
    controller.bindUser('member');
    await tester.pump();
    await tester.pump();
  }

  group('StreakIndicator', () {
    testWidgets('shows nothing before the backend confirms a streak', (
      tester,
    ) async {
      await tester.pumpWidget(app(const StreakIndicator()));
      expect(find.byKey(StreakIndicator.tapTargetKey), findsNothing);
    });

    testWidgets('renders the current streak with a meaningful label', (
      tester,
    ) async {
      await tester.pumpWidget(app(const StreakIndicator()));
      await signIn(tester, streakResult(current: 8));
      await tester.pumpAndSettle();

      expect(find.text('8'), findsOneWidget);
      expect(find.bySemanticsLabel('Daily streak: 8 days'), findsOneWidget);
      final size = tester.getSize(find.byKey(StreakIndicator.tapTargetKey));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('disappears for the next user until their streak loads', (
      tester,
    ) async {
      await tester.pumpWidget(app(const StreakIndicator()));
      await signIn(tester, streakResult(current: 8));
      await tester.pumpAndSettle();
      expect(find.text('8'), findsOneWidget);

      controller.bindUser(null);
      await tester.pump();
      expect(find.text('8'), findsNothing);
    });

    testWidgets('opens the details sheet on tap', (tester) async {
      await tester.pumpWidget(app(const StreakIndicator()));
      await signIn(tester, streakResult(current: 8, longest: 12, total: 34));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(StreakIndicator.tapTargetKey));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('streak-details')), findsOneWidget);
      expect(find.text('Daily streak'), findsOneWidget);
      expect(find.text('8-day streak'), findsOneWidget);
      expect(
        find.text('You have come back to Mevora 8 days in a row.'),
        findsOneWidget,
      );
      expect(find.text('Longest streak: 12 days'), findsOneWidget);
      expect(find.text('34 days on Mevora in total'), findsOneWidget);
      expect(analytics.events, contains('streak_details_viewed'));
    });

    testWidgets('fits the app bar at a large text scale', (tester) async {
      await tester.pumpWidget(app(const StreakIndicator(), textScale: 2));
      await signIn(tester, streakResult(current: 128, longest: 128));
      await tester.pumpAndSettle();
      expect(find.text('128'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not animate the number under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const StreakIndicator(), disableAnimations: true),
      );
      await signIn(tester, streakResult(current: 5));
      expect(
        find.descendant(
          of: find.byKey(StreakIndicator.tapTargetKey),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('StreakDetailsContent', () {
    Widget details(
      DailyStreak streak, {
      Locale locale = const Locale('en'),
      double textScale = 1,
    }) {
      return MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: StreakDetailsContent(streak: streak),
            ),
          ),
        ),
      );
    }

    const eight = DailyStreak(
      currentStreak: 8,
      longestStreak: 12,
      totalCheckInDays: 34,
      dayKey: '2026-09-29',
    );

    testWidgets('reads naturally in Turkish', (tester) async {
      await tester.pumpWidget(details(eight, locale: const Locale('tr')));
      await tester.pumpAndSettle();

      expect(find.text('8 günlük seri'), findsOneWidget);
      expect(
        find.text("8 gündür Mevora'ya her gün dönüyorsun."),
        findsOneWidget,
      );
      expect(find.text('En uzun serin: 12 gün'), findsOneWidget);
      expect(find.text("Mevora'da toplam 34 gün"), findsOneWidget);
      expect(find.text('Son 7 gün'), findsOneWidget);
    });

    testWidgets('uses the singular for a one-day streak', (tester) async {
      const one = DailyStreak(
        currentStreak: 1,
        longestStreak: 1,
        totalCheckInDays: 1,
        dayKey: '2026-09-29',
      );
      await tester.pumpWidget(details(one));
      await tester.pumpAndSettle();
      expect(find.text('1-day streak'), findsOneWidget);
      expect(find.text('Longest streak: 1 day'), findsOneWidget);
      expect(find.text('1 day on Mevora in total'), findsOneWidget);

      await tester.pumpWidget(details(one, locale: const Locale('tr')));
      await tester.pumpAndSettle();
      expect(find.text('1 günlük seri'), findsOneWidget);
      expect(find.textContaining('günler'), findsNothing);
    });

    testWidgets('says how a streak works without shaming a missed day', (
      tester,
    ) async {
      await tester.pumpWidget(details(eight));
      await tester.pumpAndSettle();
      expect(find.textContaining('same day does not add'), findsOneWidget);
      expect(
        find.textContaining('longest streak always stays'),
        findsOneWidget,
      );
      expect(find.textContaining('lost'), findsNothing);
    });

    testWidgets('marks the days the current streak covers', (tester) async {
      expect(StreakWeekRow.coveredDays(3), [
        false,
        false,
        false,
        false,
        true,
        true,
        true,
      ]);
      expect(StreakWeekRow.coveredDays(12), List.filled(7, true));

      await tester.pumpWidget(details(eight));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('You came back on 7 of the last 7 days'),
        findsOneWidget,
      );
    });

    testWidgets('lays out without overflow at a large text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        details(eight, locale: const Locale('tr'), textScale: 2),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('StreakCelebrationHost', () {
    Widget host({
      Locale locale = const Locale('en'),
      bool disableAnimations = false,
    }) {
      return StreakScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: inner!,
          ),
          home: const StreakCelebrationHost(
            delay: Duration(milliseconds: 10),
            child: Scaffold(body: Text('home')),
          ),
        ),
      );
    }

    Finder celebration() => find.byKey(const ValueKey('streak-celebration'));

    testWidgets('celebrates a credited day once', (tester) async {
      await tester.pumpWidget(host());
      await signIn(tester, streakResult(current: 8));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      expect(celebration(), findsOneWidget);
      expect(find.text('8-day streak'), findsOneWidget);
      expect(find.text('You kept your streak going today.'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(celebration(), findsNothing);

      // Same day again: the backend says alreadyCounted.
      repository.enqueue(streakResult(status: CheckInStatus.alreadyCounted));
      await controller.refresh(force: true);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(celebration(), findsNothing);
    });

    testWidgets('does not celebrate a same-day result', (tester) async {
      await tester.pumpWidget(host());
      await signIn(tester, streakResult(status: CheckInStatus.alreadyCounted));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(celebration(), findsNothing);
    });

    testWidgets('welcomes a first day', (tester) async {
      await tester.pumpWidget(host(locale: const Locale('tr')));
      await signIn(
        tester,
        streakResult(
          status: CheckInStatus.started,
          current: 1,
          longest: 1,
          total: 1,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('Serin başladı'), findsOneWidget);
      expect(
        find.text("Bugün Mevora'ya geldin. Yarın devam edebilirsin."),
        findsOneWidget,
      );
    });

    testWidgets('frames a reset as a new start, not a loss', (tester) async {
      await tester.pumpWidget(host(locale: const Locale('tr')));
      await signIn(
        tester,
        streakResult(
          status: CheckInStatus.reset,
          current: 1,
          longest: 5,
          total: 21,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('Yeni bir seri başladı'), findsOneWidget);
      expect(find.textContaining('kaybettin'), findsNothing);
    });

    testWidgets('marks a personal best and a milestone', (tester) async {
      await tester.pumpWidget(host());
      await signIn(
        tester,
        streakResult(
          current: 7,
          longest: 7,
          newPersonalBest: true,
          milestone: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('New personal best'), findsOneWidget);
      expect(find.text('Milestone'), findsOneWidget);
    });

    testWidgets('shows a still ember under reduced motion', (tester) async {
      await tester.pumpWidget(host(disableAnimations: true));
      await signIn(tester, streakResult(current: 3, milestone: true));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(celebration(), findsOneWidget);
      expect(
        find.descendant(
          of: celebration(),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
      );
    });
  });
}
