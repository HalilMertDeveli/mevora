import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';

class _RecordingAnalytics implements AnalyticsProvider {
  final List<String> events = <String>[];
  final List<Map<String, Object>?> parameters = <Map<String, Object>?>[];

  Iterable<String> get calibrationEvents =>
      events.where((name) => name.startsWith('humor_calibration_'));

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add(name);
    this.parameters.add(parameters);
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

/// Serves a scripted sequence of feed pages; everything else is unused.
class _ScriptedFeedRepository implements HumorRepository {
  _ScriptedFeedRepository(this.pages);

  final List<HumorFeedPage> pages;
  final List<String?> cursors = <String?>[];

  @override
  Future<Result<HumorFeedPage>> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  }) async {
    cursors.add(cursor);
    final index = cursors.length - 1;
    return Success(
      index < pages.length ? pages[index] : const HumorFeedPage(items: []),
    );
  }

  @override
  Future<Result<UserHumorProfile>> getProfile({bool detailed = false}) async =>
      const Success(UserHumorProfile.empty);

  @override
  Future<Result<HumorFeedbackResult>> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool? swipeUp,
    bool? swipeDown,
  }) => throw UnimplementedError();

  @override
  Future<Result<HumorFeedbackResult>> skipContent({
    required String contentId,
    String? skipReason,
  }) => throw UnimplementedError();

  @override
  Future<Result<HumorCompatibility>> getMatchCompatibility(String matchId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) => throw UnimplementedError();

  @override
  Future<Result<HumorDailySet>> getDailySet() => throw UnimplementedError();

  @override
  Future<Result<HumorDailySubmitOutcome>> submitDailyResponse({
    required String dayId,
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
  }) => throw UnimplementedError();

  @override
  Future<Result<HumorDailySubmitOutcome>> skipDailyItem({
    required String dayId,
    required String contentId,
  }) => throw UnimplementedError();
}

const _item = HumorContent(
  contentId: 'late_item',
  type: HumorContentType.text,
  language: 'tr',
  category: HumorCategory.dry,
  textBody: 'Evet.',
);

HumorController _build(
  MockHumorDataSource source, {
  AnalyticsProvider? analytics,
}) {
  return HumorController(
    repository: HumorRepositoryImpl(dataSource: source),
    analytics: analytics,
  );
}

/// How many items the initial calibration has on the mock server.
const _total = MockHumorDataSource.onboardingCount;

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

void main() {
  test('load populates feed from mock datasource', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);

    await controller.load();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.failure, isNull);
    expect(controller.state.items, isNotEmpty);
    expect(controller.state.current?.contentId, 'hc_tr_vid_001');
    expect(controller.state.current?.type, HumorContentType.video);
    expect(controller.state.current?.language, 'tr');
    expect(controller.state.current?.hasMedia, isTrue);
    expect(source.feedCalls, 1);
  });

  test('rate advances one card and the new card shows no rating', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();

    await controller.rate(HumorRating.veryFunny);

    expect(controller.state.currentIndex, 1);
    expect(controller.state.canGoBack, isTrue);
    expect(
      controller.state.lastRated,
      isNull,
      reason: 'the next card is unrated and must not look pre-rated',
    );
    expect(controller.state.isSubmitting, isFalse);
    expect(source.feedbackCalls, 1);
    expect(source.profile.interactionCount, 1);
  });

  test('previous item shows its rating; re-rating replaces it', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();
    final first = controller.state.current!.contentId;
    await controller.rate(HumorRating.funny);
    expect(controller.state.currentIndex, 1);

    controller.goBack();

    expect(controller.state.currentIndex, 0);
    expect(controller.state.lastRated, HumorRating.funny);
    expect(controller.state.canGoBack, isFalse);

    await controller.rate(HumorRating.notAtAll);

    expect(source.ratingOf(first), HumorRating.notAtAll);
    expect(
      source.profile.interactionCount,
      1,
      reason: 'changing a rating replaces it, it is not a second rating',
    );
    expect(controller.state.calibration.completedCount, 1);
    expect(controller.state.currentIndex, 1);
    expect(controller.state.lastRated, isNull);
  });

  test(
    'a double tap (or tap plus swipe) submits once and moves one card',
    () async {
      final source = MockHumorDataSource();
      final controller = _build(source);
      await controller.load();
      final first = controller.state.current!.contentId;
      final gate = Completer<void>();
      source.feedbackGate = gate;

      final firstTap = controller.rate(HumorRating.funny);
      expect(controller.state.isSubmitting, isTrue);
      expect(controller.state.canAct, isFalse);
      final secondTap = controller.rate(HumorRating.veryFunny);
      final swipe = controller.rateSwipeUp();
      final skip = controller.skipUnplayable(first);
      gate.complete();
      await Future.wait([firstTap, secondTap, swipe, skip]);

      expect(source.feedbackCalls, 1);
      expect(source.ratingOf(first), HumorRating.funny);
      expect(controller.state.currentIndex, 1);
      expect(controller.state.isSubmitting, isFalse);
    },
  );

  test('a failed rating does not advance, is reported once, and a retry '
      'advances exactly one card', () async {
    final source = MockHumorDataSource()..failFeedback = true;
    final controller = _build(source);
    await controller.load();

    await controller.rate(HumorRating.funny);

    expect(controller.state.currentIndex, 0);
    expect(controller.state.calibration.completedCount, 0);
    expect(controller.state.actionFailure, isA<UnexpectedFailure>());
    expect(controller.state.actionFailureId, 1);
    expect(controller.state.isSubmitting, isFalse);
    expect(
      controller.state.failure,
      isNull,
      reason: 'cards stay on screen; this is not a load failure',
    );

    source.failFeedback = false;
    await controller.retryFailedAction();

    expect(controller.state.currentIndex, 1);
    expect(controller.state.calibration.completedCount, 1);
    expect(controller.state.actionFailureId, 1);
    expect(source.profile.interactionCount, 1);

    // The retry is consumed: running it again changes nothing.
    await controller.retryFailedAction();
    expect(controller.state.currentIndex, 1);
    expect(source.feedbackCalls, 2);
  });

  test('there is no "not interested": the only skip is media that would not '
      'play', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();
    final skipped = controller.state.current!.contentId;

    await controller.skipUnplayable(skipped);

    expect(controller.state.currentIndex, 1);
    expect(source.skipCalls, 1);
    expect(source.skipReasons, [HumorSkipReason.mediaFailed]);
    expect(source.deferredContentIds, contains(skipped));
    expect(source.ratingOf(skipped), isNull);
    expect(source.profile.interactionCount, 0);
    expect(controller.state.calibration.completedCount, 0);

    // Done for today — and nothing else is put in its place.
    await controller.load();
    expect(
      controller.state.items.map((item) => item.contentId),
      source.sequenceIds.sublist(1, _total),
    );

    // It is the same measurement for everyone, so it comes back tomorrow.
    source.closeDay('2099-01-02');
    await controller.load();
    expect(controller.state.current?.contentId, skipped);
  });

  test('rating passed content later counts as its first rating', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();
    await controller.skipUnplayable(controller.state.current!.contentId);

    controller.goBack();
    expect(controller.state.currentIndex, 0);
    expect(controller.state.lastRated, isNull);

    await controller.rate(HumorRating.veryFunny);

    expect(source.profile.interactionCount, 1);
    expect(controller.state.calibration.completedCount, 1);
    expect(controller.state.currentIndex, 1);
  });

  test('reporting moves past the card without rating it', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();
    final reported = controller.state.current!.contentId;

    final result = await controller.reportCurrent('spam');

    expect(result?.isSuccess, isTrue);
    expect(source.reportCalls, 1);
    expect(source.ratingOf(reported), isNull);
    expect(source.profile.interactionCount, 0);
    expect(controller.state.currentIndex, 1);
    expect(
      controller.state.canGoBack,
      isFalse,
      reason: 'a reported card must not be offered again',
    );

    await controller.load();
    expect(
      controller.state.items.map((item) => item.contentId),
      isNot(contains(reported)),
    );
  });

  test('a failed report keeps the card and is reported once', () async {
    final source = MockHumorDataSource()..failReport = true;
    final controller = _build(source);
    await controller.load();

    final result = await controller.reportCurrent('other');

    expect(result?.isError, isTrue);
    expect(controller.state.currentIndex, 0);
    expect(controller.state.actionFailureId, 1);
  });

  test('the whole calibration arrives at once and runs to its end', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();

    // Nothing is chosen from the answers: every item is known up front.
    expect(controller.state.items, hasLength(_total));
    expect(controller.state.nextCursor, isNull);
    final served = controller.state.items.map((item) => item.contentId);
    expect(served, source.sequenceIds.take(_total));

    for (var i = 0; i < _total; i += 1) {
      expect(controller.state.current?.contentId, source.sequenceIds[i]);
      expect(controller.state.reachedEnd, isFalse);
      await controller.rate(HumorRating.funny);
    }

    expect(controller.state.calibration.complete, isTrue);
    expect(controller.state.calibration.completedCount, _total);
    expect(controller.state.items, hasLength(_total));
    expect(
      source.feedCalls,
      1,
      reason: 'one page, and no page fetched as calibration ends',
    );
    expect(source.feedbackCalls, _total);
  });

  test('only the rating that finishes calibration sets the hand-off', () async {
    final source = MockHumorDataSource();
    await _preRate(source, _total - 1);
    final controller = _build(source);
    await controller.load();
    expect(controller.state.calibrationJustCompleted, isFalse);

    await controller.rate(HumorRating.funny);

    expect(controller.state.calibration.complete, isTrue);
    expect(controller.state.calibrationJustCompleted, isTrue);
    controller.consumeCalibrationCompleted();
    expect(controller.state.calibrationJustCompleted, isFalse);

    // There is nothing to continue with: the next items are tomorrow's.
    await controller.loadMore();
    expect(controller.state.current, isNull);
    expect(controller.state.calibrationJustCompleted, isFalse);
  });

  test(
    'opening the Lab as a calibrated user never counts as finishing',
    () async {
      final source = MockHumorDataSource()..completeCalibration();
      final controller = _build(source);

      await controller.load();

      expect(controller.state.calibration.complete, isTrue);
      expect(controller.state.calibrationJustCompleted, isFalse);
      // The feed is closed: the daily tour is where new items are.
      expect(controller.state.items, isEmpty);
      expect(controller.state.catalogExhausted, isTrue);
      expect(controller.state.catalogEmpty, isFalse);
    },
  );

  test('the end is reported, and the last card cannot be rated '
      'again', () async {
    final source = MockHumorDataSource();
    await _preRate(source, _total - 2);
    final controller = _build(source);
    await controller.load();
    expect(controller.state.items, hasLength(2));

    await controller.rate(HumorRating.funny);
    await controller.rate(HumorRating.funny);
    await controller.loadMore();

    expect(controller.state.current, isNull);
    expect(controller.state.atTail, isTrue);
    expect(controller.state.reachedEnd, isTrue);
    expect(controller.state.catalogExhausted, isTrue);
    expect(controller.state.canAct, isFalse);

    final calls = source.feedbackCalls;
    await controller.rate(HumorRating.veryFunny);
    expect(source.feedbackCalls, calls, reason: 'nothing left to rate');
  });

  test('follows empty pages that still carry a cursor', () async {
    final repository = _ScriptedFeedRepository([
      const HumorFeedPage(items: [], nextCursor: 'c1'),
      const HumorFeedPage(items: [], nextCursor: 'c2'),
      const HumorFeedPage(items: [_item]),
    ]);
    final controller = HumorController(repository: repository);

    await controller.load();

    expect(controller.state.current?.contentId, 'late_item');
    expect(repository.cursors, [null, 'c1', 'c2']);
  });

  test('stops following empty pages after a bounded number of hops', () async {
    final repository = _ScriptedFeedRepository([
      for (var i = 0; i < 10; i += 1)
        HumorFeedPage(items: const [], nextCursor: 'c$i'),
    ]);
    final controller = HumorController(repository: repository);

    await controller.load();

    expect(repository.cursors, hasLength(1 + HumorController.maxEmptyPageHops));
    expect(controller.state.isEmpty, isTrue);
  });

  test('only one feed request is in flight at a time', () async {
    final source = MockHumorDataSource();
    await _preRate(source, _total - 1);
    final controller = _build(source);
    await controller.load();
    await controller.rate(HumorRating.funny);
    final before = source.feedCalls;

    await Future.wait([controller.loadMore(), controller.loadMore()]);

    expect(source.feedCalls, before + 1);
  });

  test('a request settling after dispose does not notify', () async {
    final source = MockHumorDataSource();
    final controller = _build(source);
    await controller.load();
    final gate = Completer<void>();
    source.feedbackGate = gate;

    final pending = controller.rate(HumorRating.funny);
    controller.dispose();
    gate.complete();

    await expectLater(pending, completes);
  });

  group('calibration analytics', () {
    test('loading logs no calibration event', () async {
      final analytics = _RecordingAnalytics();
      final source = MockHumorDataSource()..completeCalibration();

      await _build(source, analytics: analytics).load();
      await _build(MockHumorDataSource(), analytics: analytics).load();

      expect(analytics.calibrationEvents, isEmpty);
    });

    test('progress per counted rating, completion exactly once', () async {
      final analytics = _RecordingAnalytics();
      final source = MockHumorDataSource();
      await _preRate(source, _total - 2);
      final controller = _build(source, analytics: analytics);
      await controller.load();

      await controller.rate(HumorRating.funny); // one left
      controller.goBack();
      await controller.rate(HumorRating.notFunny); // re-rate: not counted
      await controller.rate(HumorRating.funny); // the last one

      expect(analytics.calibrationEvents.toList(), [
        AnalyticsEvents.humorCalibrationProgress,
        AnalyticsEvents.humorCalibrationCompleted,
      ]);
      expect(
        analytics.events,
        isNot(contains(AnalyticsEvents.humorCalibrationStarted)),
      );
      for (final parameters in analytics.parameters) {
        for (final value in parameters?.values ?? const <Object>[]) {
          expect(value is String || value is num, isTrue);
        }
      }
    });
  });

  test('empty feed surfaces empty state', () async {
    final source = MockHumorDataSource(seed: const <HumorContent>[]);
    final controller = _build(source);

    await controller.load();

    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.items, isEmpty);
  });

  test('feed error surfaces failure', () async {
    final source = MockHumorDataSource()..failFeed = true;
    final controller = _build(source);

    await controller.load();

    expect(controller.state.failure, isNotNull);
    expect(controller.state.items, isEmpty);
    expect(controller.state.isLoading, isFalse);
  });
}
