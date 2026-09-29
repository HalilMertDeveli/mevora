import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/streak/data/streak_analytics.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';

import 'streak_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedStreakRepository repository;
  late RecordingAnalytics analytics;
  late DateTime now;
  late DailyStreakController controller;

  DailyStreakController build({
    List<Duration> retryDelays = const [Duration(milliseconds: 5)],
  }) {
    return DailyStreakController(
      repository: repository,
      analytics: StreakAnalytics(analytics),
      clock: () => now,
      retryDelays: retryDelays,
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repository = ScriptedStreakRepository();
    analytics = RecordingAnalytics();
    now = DateTime(2026, 9, 29, 15);
    controller = build();
  });

  tearDown(() => controller.dispose());

  group('member binding', () {
    test('does nothing until a member is bound', () async {
      await controller.refresh();
      expect(repository.calls, 0);
      expect(controller.streak, isNull);
    });

    test('checks in on first load and holds the confirmed streak', () async {
      repository.enqueue(
        streakResult(
          status: CheckInStatus.started,
          current: 1,
          longest: 1,
          total: 1,
        ),
      );
      controller.bindUser('a');
      await settle();

      expect(repository.calls, 1);
      expect(repository.offsets.single, now.timeZoneOffset.inMinutes);
      expect(controller.streak?.currentStreak, 1);
      expect(controller.hasError, isFalse);
    });

    test('a credited day queues exactly one celebration', () async {
      repository.enqueue(streakResult(current: 8));
      controller.bindUser('a');
      await settle();

      final celebration = controller.takeCelebration();
      expect(celebration?.streak.currentStreak, 8);
      expect(controller.takeCelebration(), isNull);
      expect(controller.pendingCelebration, isNull);
    });

    test('a same-day result shows the streak without celebrating', () async {
      repository.enqueue(
        streakResult(status: CheckInStatus.alreadyCounted, current: 8),
      );
      controller.bindUser('a');
      await settle();

      expect(controller.streak?.currentStreak, 8);
      expect(controller.pendingCelebration, isNull);
      expect(analytics.events, isEmpty);
    });

    test('an ineligible account shows no streak', () async {
      repository.enqueue(
        streakResult(
          status: CheckInStatus.ineligible,
          current: 0,
          longest: 0,
          total: 0,
        ),
      );
      controller.bindUser('a');
      await settle();

      expect(controller.streak, isNull);
      expect(controller.pendingCelebration, isNull);
    });

    test('signing out clears the previous member at once', () async {
      repository.enqueue(streakResult(current: 5));
      controller.bindUser('a');
      await settle();
      expect(controller.streak, isNotNull);

      controller.bindUser(null);
      expect(controller.streak, isNull);
      expect(controller.pendingCelebration, isNull);
    });

    test('a different user never sees the previous user\'s streak', () async {
      repository.enqueue(streakResult(current: 5));
      controller.bindUser('a');
      await settle();

      repository.enqueue(
        streakResult(
          status: CheckInStatus.started,
          current: 1,
          longest: 1,
          total: 1,
        ),
      );
      controller.bindUser('b');
      expect(controller.streak, isNull, reason: 'cleared before B loads');
      await settle();
      expect(controller.streak?.currentStreak, 1);
    });

    test('a slow response for the previous user is discarded', () async {
      repository.gate = Completer<void>();
      repository
        ..enqueue(streakResult(current: 42)) // A's answer, arriving late
        ..enqueue(
          streakResult(
            status: CheckInStatus.started,
            current: 1,
            longest: 1,
            total: 1,
          ),
        );
      controller.bindUser('a');
      controller.bindUser('b');
      repository.gate!.complete();
      repository.gate = null;
      await settle();
      await settle();

      expect(controller.uid, 'b');
      expect(controller.streak?.currentStreak, 1);
    });

    test('rebinding the same member does not check in again', () async {
      repository.enqueue(streakResult());
      controller.bindUser('a');
      await settle();
      controller.bindUser('a');
      await settle();
      expect(repository.calls, 1);
    });
  });

  group('lifecycle', () {
    test('resume on the same day does not call the backend again', () async {
      repository.enqueue(streakResult());
      controller.bindUser('a');
      await settle();

      now = now.add(const Duration(hours: 3));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(repository.calls, 1);
    });

    test('resume on a new local day checks in once', () async {
      repository.enqueue(streakResult(current: 8));
      controller.bindUser('a');
      await settle();
      controller.takeCelebration();

      now = DateTime(2026, 9, 30, 9);
      repository.enqueue(streakResult(current: 9, dayKey: '2026-09-30'));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(repository.calls, 2);
      expect(controller.streak?.currentStreak, 9);
      expect(controller.pendingCelebration?.streak.currentStreak, 9);
    });

    test('concurrent triggers share one request', () async {
      repository.gate = Completer<void>();
      repository.enqueue(streakResult());
      controller.bindUser('a');
      unawaited(controller.refresh(force: true));
      unawaited(controller.refresh(force: true));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      repository.gate!.complete();
      await settle();
      await settle();
      expect(repository.calls, 1);
    });

    test(
      'lifecycle events moments apart are throttled after a failure',
      () async {
        controller.dispose();
        controller = build(retryDelays: const []);
        repository.enqueue(StateError('offline'));
        controller.bindUser('a');
        await settle();

        now = now.add(const Duration(seconds: 2));
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await settle();
        expect(repository.calls, 1);

        now = now.add(const Duration(minutes: 1));
        repository.enqueue(streakResult());
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await settle();
        expect(repository.calls, 2);
        expect(controller.hasError, isFalse);
      },
    );
  });

  group('failures', () {
    test(
      'a network failure keeps the last known streak and never invents one',
      () async {
        repository.enqueue(streakResult(current: 8));
        controller.bindUser('a');
        await settle();
        controller.takeCelebration();

        now = DateTime(2026, 9, 30, 9);
        repository.enqueue(StateError('unavailable'));
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await settle();

        expect(controller.hasError, isTrue);
        expect(controller.streak?.currentStreak, 8, reason: 'not 9, not 0');
        expect(controller.pendingCelebration, isNull);
      },
    );

    test('a failure on first load leaves nothing to show', () async {
      controller.dispose();
      controller = build(retryDelays: const []);
      repository.enqueue(StateError('unavailable'));
      controller.bindUser('a');
      await settle();

      expect(controller.hasError, isTrue);
      expect(controller.streak, isNull);
    });

    test('retries on its own after a failure and reconciles', () async {
      repository
        ..enqueue(StateError('unavailable'))
        ..enqueue(streakResult(current: 3, dayKey: '2026-09-29'));
      controller.bindUser('a');
      await settle();
      expect(controller.hasError, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repository.calls, 2);
      expect(controller.hasError, isFalse);
      expect(controller.streak?.currentStreak, 3);
      expect(controller.pendingCelebration, isNotNull);
    });

    test('stops retrying after the configured attempts', () async {
      controller.dispose();
      controller = build(
        retryDelays: const [
          Duration(milliseconds: 2),
          Duration(milliseconds: 2),
        ],
      );
      repository.enqueue(StateError('down'));
      controller.bindUser('a');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repository.calls, 3);
    });

    test('signing out cancels a pending retry', () async {
      controller.dispose();
      controller = build(retryDelays: const [Duration(milliseconds: 10)]);
      repository.enqueue(StateError('down'));
      controller.bindUser('a');
      await settle();
      controller.bindUser(null);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repository.calls, 1);
    });
  });

  group('analytics', () {
    test('logs a credited day with coarse, non-identifying params', () async {
      repository.enqueue(
        streakResult(current: 13, longest: 13, newPersonalBest: true),
      );
      controller.bindUser('a');
      await settle();

      expect(analytics.events, ['streak_check_in', 'streak_personal_best']);
      final params = analytics.parameters.first!;
      expect(params, {
        'status': 'continued',
        'streak_length_bucket': '8_14',
        'personal_best': 1,
      });
      for (final p in analytics.parameters) {
        expect(p!.keys, isNot(contains('uid')));
        expect(p.values, isNot(contains('a')));
      }
    });

    test('buckets streak lengths', () {
      expect(StreakAnalytics.lengthBucket(1), '1');
      expect(StreakAnalytics.lengthBucket(3), '2_3');
      expect(StreakAnalytics.lengthBucket(7), '4_7');
      expect(StreakAnalytics.lengthBucket(30), '15_30');
      expect(StreakAnalytics.lengthBucket(365), '100_plus');
    });
  });

  group('streakMemberUid', () {
    const member = AuthUser(id: 'm', onboardingCompleted: true);
    const newcomer = AuthUser(id: 'n');

    test('binds only a member who finished onboarding', () {
      expect(streakMemberUid(const Authenticated(member)), 'm');
      expect(
        streakMemberUid(
          const Authenticated(AuthUser(id: 'p', profileCompleted: true)),
        ),
        'p',
      );
      expect(streakMemberUid(const Authenticated(newcomer)), isNull);
      expect(streakMemberUid(const NeedsOnboarding(newcomer)), isNull);
    });

    test('clears on sign-out and auth errors', () {
      expect(streakMemberUid(AuthStatus.unauthenticated, current: 'm'), isNull);
      expect(
        streakMemberUid(const AuthenticationError('x'), current: 'm'),
        isNull,
      );
    });

    test('keeps the bound member through transient states', () {
      expect(streakMemberUid(AuthStatus.unknown, current: 'm'), 'm');
      expect(streakMemberUid(AuthStatus.authenticating, current: 'm'), 'm');
    });
  });
}
