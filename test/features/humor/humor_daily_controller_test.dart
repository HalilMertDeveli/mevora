import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_daily_controller.dart';

class _RecordingAnalytics implements AnalyticsProvider {
  final List<(String, Map<String, Object>?)> events = [];

  Iterable<String> get names => events.map((e) => e.$1);

  Map<String, Object>? last(String name) =>
      events.lastWhere((e) => e.$1 == name).$2;

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name, parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

/// A mock backend whose user has finished calibration, so a day is served.
Future<MockHumorDataSource> _calibratedSource() async {
  final source = MockHumorDataSource();
  for (var i = 0; i < 15; i += 1) {
    await source.submitFeedback(contentId: 'cal_$i', rating: HumorRating.funny);
  }
  return source;
}

HumorDailyController _controller(
  MockHumorDataSource source, {
  AnalyticsProvider? analytics,
}) => HumorDailyController(
  repository: HumorRepositoryImpl(dataSource: source),
  analytics: analytics,
);

void main() {
  test('a fresh day starts at the first item, 1/10', () async {
    final source = await _calibratedSource();
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);

    await controller.load();

    final state = controller.state;
    expect(state.isReady, isTrue);
    expect(state.currentIndex, 0);
    expect(state.position, 1);
    expect(state.total, 10);
    expect(state.current?.contentId, state.set!.items.first.contentId);
    expect(analytics.last(AnalyticsEvents.dailyHumorStarted), {'position': 1});
  });

  test('resumes after 3 of 10 at the fourth item', () async {
    final source = await _calibratedSource();
    source.seedDailyProgress(3);
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);

    await controller.load();

    expect(controller.state.currentIndex, 3);
    expect(controller.state.position, 4);
    expect(
      controller.state.current?.contentId,
      controller.state.set!.items[3].contentId,
    );
    expect(analytics.last(AnalyticsEvents.dailyHumorResume), {'position': 4});
    expect(analytics.names, isNot(contains(AnalyticsEvents.dailyHumorStarted)));
  });

  test('resumes after 9 of 10 at the last item', () async {
    final source = await _calibratedSource();
    source.seedDailyProgress(9);
    final controller = _controller(source);

    await controller.load();

    expect(controller.state.currentIndex, 9);
    expect(controller.state.position, 10);
    expect(
      controller.state.current?.contentId,
      controller.state.set!.items[9].contentId,
    );
  });

  test('a double tap submits once and advances once', () async {
    final source = await _calibratedSource();
    final controller = _controller(source);
    await controller.load();
    final gate = Completer<void>();
    source.dailyGate = gate;

    final first = controller.rate(HumorRating.funny);
    expect(controller.state.isSubmitting, isTrue);
    expect(controller.state.canAct, isFalse);
    final second = controller.rate(HumorRating.veryFunny);
    gate.complete();
    await Future.wait([first, second]);

    expect(source.dailySubmitCalls, 1);
    expect(controller.state.currentIndex, 1);
    expect(source.dailyAnswers[0]!.rating, HumorRating.funny);
  });

  test('never advances before the server confirms', () async {
    final source = await _calibratedSource();
    final controller = _controller(source);
    await controller.load();
    final gate = Completer<void>();
    source.dailyGate = gate;

    final pending = controller.rate(HumorRating.funny);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.currentIndex, 0);

    gate.complete();
    await pending;
    expect(controller.state.currentIndex, 1);
  });

  test('a network failure keeps the item and a retry lands once', () async {
    final source = await _calibratedSource();
    final controller = _controller(source);
    await controller.load();
    final firstId = controller.state.current!.contentId;

    source.failDaily = true;
    await controller.rate(HumorRating.funny);

    expect(controller.state.currentIndex, 0);
    expect(controller.state.current?.contentId, firstId);
    expect(controller.state.isSubmitting, isFalse);
    expect(controller.state.actionFailure, isNotNull);
    expect(controller.state.actionFailureId, 1);

    source.failDaily = false;
    await controller.retryFailedAction();

    expect(controller.state.currentIndex, 1);
    expect(source.dailyAnswers, hasLength(1));
  });

  test('day-closed reloads and continues with the new day', () async {
    final source = await _calibratedSource();
    source.seedDailyProgress(4);
    final controller = _controller(source);
    await controller.load();
    expect(controller.state.currentIndex, 4);
    final oldDay = controller.state.set!.dayId;

    source.closeDay('2099-01-01');
    await controller.rate(HumorRating.funny);

    expect(source.dailySetCalls, 2, reason: 'the set is reloaded');
    expect(controller.state.set!.dayId, '2099-01-01');
    expect(controller.state.set!.dayId, isNot(oldDay));
    expect(controller.state.currentIndex, 0);
    expect(controller.state.set!.answeredCount, 0);
    expect(controller.state.actionFailure, isNull);
    expect(controller.state.isSubmitting, isFalse);
  });

  test('media failure passes the slot as media_failed and advances', () async {
    final source = await _calibratedSource();
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);
    await controller.load();
    final id = controller.state.current!.contentId;

    // A late "Next" from another item is ignored.
    await controller.skipUnplayable('not-on-screen');
    expect(source.dailySkipCalls, 0);

    await controller.skipUnplayable(id);

    expect(source.dailySkipCalls, 1);
    expect(source.dailyAnswers[0]!.skipped, isTrue);
    expect(source.dailyAnswers[0]!.rating, isNull);
    expect(controller.state.currentIndex, 1);
    expect(analytics.last(AnalyticsEvents.dailyHumorPlaybackFailed), {
      'position': 1,
      'reason': 'media_failed',
    });
  });

  test('the tenth answer completes the day', () async {
    final source = await _calibratedSource();
    source.seedDailyProgress(9);
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);
    await controller.load();

    await controller.rate(HumorRating.neutral);

    expect(controller.state.completed, isTrue);
    expect(controller.state.set!.answeredCount, 10);
    expect(controller.state.current, isNull);
    expect(controller.state.canAct, isFalse);
    expect(analytics.last(AnalyticsEvents.dailyHumorCompleted), {'total': 10});
    expect(analytics.last(AnalyticsEvents.dailyHumorProgress), {
      'position': 10,
      'total': 10,
    });

    // Nothing more can be submitted once the day is done.
    await controller.rate(HumorRating.funny);
    expect(source.dailySubmitCalls, 1);
  });

  test('a completed day reopens as completed, not as a new tour', () async {
    final source = await _calibratedSource();
    source.seedDailyProgress(10);
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);

    await controller.load();

    expect(controller.state.completed, isTrue);
    expect(controller.state.current, isNull);
    expect(analytics.events, isEmpty);
  });

  test('analytics carry only small scalars — no ids, lists or URLs', () async {
    final source = await _calibratedSource();
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);
    await controller.load();
    final ids = controller.state.set!.items.map((i) => i.contentId).toSet();

    await controller.rate(HumorRating.funny);
    await controller.skipUnplayable(controller.state.current!.contentId);
    for (var i = 0; i < 8; i += 1) {
      await controller.rate(HumorRating.notAtAll);
    }
    expect(controller.state.completed, isTrue);

    expect(
      analytics.names,
      containsAll(<String>[
        AnalyticsEvents.dailyHumorStarted,
        AnalyticsEvents.dailyHumorProgress,
        AnalyticsEvents.dailyHumorPlaybackFailed,
        AnalyticsEvents.dailyHumorCompleted,
      ]),
    );
    for (final (name, parameters) in analytics.events) {
      expect(name, startsWith('daily_humor_'));
      for (final value in (parameters ?? const {}).values) {
        expect(value, anyOf(isA<int>(), isA<String>()), reason: name);
        if (value is String) {
          expect(ids, isNot(contains(value)), reason: name);
          expect(value, isNot(contains('http')), reason: name);
          expect(value.length, lessThan(40), reason: name);
        }
      }
    }
  });
}
