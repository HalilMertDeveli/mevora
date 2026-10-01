import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
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

/// Items in a day, as the mock server serves them.
const _daySize = MockHumorDataSource.dailySetSize;

/// Items in the initial calibration on the mock server.
const _calibration = MockHumorDataSource.onboardingCount;

/// A mock backend whose user finished calibration on an earlier day, so a
/// day is served.
MockHumorDataSource _calibratedSource() =>
    MockHumorDataSource()..completeCalibration();

HumorDailyController _controller(
  MockHumorDataSource source, {
  AnalyticsProvider? analytics,
}) => HumorDailyController(
  repository: HumorRepositoryImpl(dataSource: source),
  analytics: analytics,
);

List<String> _ids(HumorDailyController controller) =>
    controller.state.set!.items.map((item) => item.contentId).toList();

void main() {
  test('the server serves five items a day', () {
    expect(_daySize, 5);
  });

  test('a fresh day starts at the first item, 1/5', () async {
    final source = _calibratedSource();
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);

    await controller.load();

    final state = controller.state;
    expect(state.isReady, isTrue);
    expect(state.currentIndex, 0);
    expect(state.position, 1);
    expect(state.total, _daySize);
    expect(state.current?.contentId, state.set!.items.first.contentId);
    expect(analytics.last(AnalyticsEvents.dailyHumorStarted), {'position': 1});
  });

  test('the day holds the next items of the sequence, in order', () async {
    final source = _calibratedSource();
    final controller = _controller(source);

    await controller.load();

    expect(
      _ids(controller),
      source.sequenceIds.sublist(_calibration, _calibration + _daySize),
    );
  });

  test('resumes after 2 of 5 at the third item', () async {
    final source = _calibratedSource();
    source.seedDailyProgress(2);
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);

    await controller.load();

    expect(controller.state.currentIndex, 2);
    expect(controller.state.position, 3);
    expect(
      controller.state.current?.contentId,
      controller.state.set!.items[2].contentId,
    );
    // The day is the same five — the two already answered are still in it.
    expect(controller.state.total, _daySize);
    expect(analytics.last(AnalyticsEvents.dailyHumorResume), {'position': 3});
    expect(analytics.names, isNot(contains(AnalyticsEvents.dailyHumorStarted)));
  });

  test('resumes after 4 of 5 at the last item', () async {
    final source = _calibratedSource();
    source.seedDailyProgress(4);
    final controller = _controller(source);

    await controller.load();

    expect(controller.state.currentIndex, 4);
    expect(controller.state.position, 5);
    expect(
      controller.state.current?.contentId,
      controller.state.set!.items[4].contentId,
    );
  });

  test('a double tap submits once and advances once', () async {
    final source = _calibratedSource();
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
    final source = _calibratedSource();
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

  test('answering the first item does not bring a sixth into today', () async {
    final source = _calibratedSource();
    final controller = _controller(source);
    await controller.load();
    final today = _ids(controller);
    final tomorrowFirst = source.sequenceIds[_calibration + _daySize];

    await controller.rate(HumorRating.veryFunny);

    expect(source.todayIds, today, reason: 'the day is frozen once touched');
    expect(source.todayIds, isNot(contains(tomorrowFirst)));
    expect(controller.state.total, _daySize);
    expect(controller.state.current?.contentId, today[1]);

    // Reopening — a restart, or another device — finds the same day.
    final reopened = _controller(source);
    await reopened.load();
    expect(_ids(reopened), today);
    expect(reopened.state.currentIndex, 1);
  });

  test("tomorrow's item is refused today, and nothing is learned", () async {
    final source = _calibratedSource();
    final repository = HumorRepositoryImpl(dataSource: source);
    final set = (await repository.getDailySet()).valueOrNull!;
    final before = source.profile.interactionCount;

    for (final contentId in [
      source.sequenceIds[_calibration + _daySize], // tomorrow's first
      source.sequenceIds.first, // an earlier one
      'anything-the-client-made-up',
    ]) {
      final outcome = await repository.submitDailyResponse(
        dayId: set.dayId,
        contentId: contentId,
        rating: HumorRating.veryFunny,
      );
      expect(
        outcome.valueOrNull,
        isA<HumorDailyStale>().having(
          (stale) => stale.reason,
          'reason',
          HumorDailyStaleReason.slotReplaced,
        ),
        reason: contentId,
      );
    }
    expect(source.profile.interactionCount, before);
    expect(source.dailyAnswers, isEmpty);
  });

  test('a network failure keeps the item and a retry lands once', () async {
    final source = _calibratedSource();
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
    final source = _calibratedSource();
    source.seedDailyProgress(2);
    final controller = _controller(source);
    await controller.load();
    expect(controller.state.currentIndex, 2);
    final oldDay = controller.state.set!.dayId;
    final unfinished = _ids(controller).sublist(2);

    source.closeDay('2099-01-01');
    await controller.rate(HumorRating.funny);

    expect(source.dailySetCalls, 2, reason: 'the set is reloaded');
    expect(controller.state.set!.dayId, '2099-01-01');
    expect(controller.state.set!.dayId, isNot(oldDay));
    expect(controller.state.currentIndex, 0);
    expect(controller.state.set!.answeredCount, 0);
    expect(controller.state.actionFailure, isNull);
    expect(controller.state.isSubmitting, isFalse);
    // What was left of yesterday leads the new day; nothing was skipped.
    expect(_ids(controller).take(unfinished.length), unfinished);
    expect(controller.state.total, _daySize);
  });

  test('the next day brings the next five, and missed days change '
      'nothing', () async {
    final source = _calibratedSource();
    final controller = _controller(source);
    await controller.load();
    while (controller.state.current != null) {
      await controller.rate(HumorRating.funny);
    }
    expect(controller.state.completed, isTrue);
    final nextFive = source.sequenceIds.sublist(
      _calibration + _daySize,
      _calibration + 2 * _daySize,
    );

    source.closeDay('2099-01-02');
    await controller.load();
    expect(_ids(controller), nextFive);

    // Away for three days: the same five are waiting, not a later range.
    source.closeDay('2099-01-05');
    await controller.load();
    expect(_ids(controller), nextFive);
    expect(controller.state.set!.answeredCount, 0);
  });

  test('media failure passes the slot as media_failed and advances', () async {
    final source = _calibratedSource();
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);
    await controller.load();
    final id = controller.state.current!.contentId;
    final before = source.profile.interactionCount;

    // A late "Next" from another item is ignored.
    await controller.skipUnplayable('not-on-screen');
    expect(source.dailySkipCalls, 0);

    await controller.skipUnplayable(id);

    expect(source.dailySkipCalls, 1);
    expect(source.dailyAnswers[0]!.skipped, isTrue);
    expect(source.dailyAnswers[0]!.rating, isNull);
    expect(source.ratingOf(id), isNull);
    expect(source.profile.interactionCount, before, reason: 'never evidence');
    expect(controller.state.currentIndex, 1);
    expect(analytics.last(AnalyticsEvents.dailyHumorPlaybackFailed), {
      'position': 1,
      'reason': 'media_failed',
    });
  });

  test('the fifth answer completes the day', () async {
    final source = _calibratedSource();
    source.seedDailyProgress(4);
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);
    await controller.load();

    await controller.rate(HumorRating.neutral);

    expect(controller.state.completed, isTrue);
    expect(controller.state.set!.answeredCount, _daySize);
    expect(controller.state.current, isNull);
    expect(controller.state.canAct, isFalse);
    expect(analytics.last(AnalyticsEvents.dailyHumorCompleted), {
      'total': _daySize,
    });
    expect(analytics.last(AnalyticsEvents.dailyHumorProgress), {
      'position': _daySize,
      'total': _daySize,
    });

    // Nothing more can be submitted once the day is done.
    await controller.rate(HumorRating.funny);
    expect(source.dailySubmitCalls, 1);
  });

  test('a completed day reopens as completed, not as a new tour', () async {
    final source = _calibratedSource();
    source.seedDailyProgress(_daySize);
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);

    await controller.load();

    expect(controller.state.completed, isTrue);
    expect(controller.state.current, isNull);
    expect(controller.state.total, _daySize);
    expect(analytics.events, isEmpty);
  });

  test('analytics carry only small scalars — no ids, lists or URLs', () async {
    final source = _calibratedSource();
    final analytics = _RecordingAnalytics();
    final controller = _controller(source, analytics: analytics);
    await controller.load();
    final ids = controller.state.set!.items.map((i) => i.contentId).toSet();

    await controller.rate(HumorRating.funny);
    await controller.skipUnplayable(controller.state.current!.contentId);
    for (var i = 0; i < _daySize - 2; i += 1) {
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
