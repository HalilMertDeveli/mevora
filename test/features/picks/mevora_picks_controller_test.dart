import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/picks/data/picks_analytics.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/controllers/mevora_picks_controller.dart';

import 'picks_fixtures.dart';

class _RecordingAnalytics implements AnalyticsProvider {
  final List<(String, Map<String, Object>?)> events = [];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name, parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {}

  List<String> get names => events.map((e) => e.$1).toList();
}

void main() {
  late FakeMevoraPicksRepository repository;
  late _RecordingAnalytics analytics;
  late MevoraPicksController controller;

  MevoraPicksBatch sixPicks() =>
      batchOf([for (var i = 0; i < 6; i++) pickPayload(uid: 'p$i', rank: i)]);

  setUp(() {
    repository = FakeMevoraPicksRepository(sixPicks());
    analytics = _RecordingAnalytics();
    controller = MevoraPicksController(
      repository: repository,
      analytics: PicksAnalytics(analytics),
      removalDuration: Duration.zero,
    );
  });

  tearDown(() => controller.dispose());

  List<String> uids() => controller.state.picks.map((p) => p.uid).toList();

  test('loads the batch and reports each Pick delivered once', () async {
    await controller.load();
    expect(controller.state.phase, PicksPhase.loaded);
    expect(uids(), ['p0', 'p1', 'p2', 'p3', 'p4', 'p5']);
    await controller.load();
    expect(
      analytics.names.where((n) => n == AnalyticsEvents.pickDelivered).length,
      6,
    );
    final params = analytics.events.first.$2!;
    expect(params['pick_type'], 'bestOverall');
    expect(params['source'], 'mevora_picks');
    expect(params['pick_id'], 'pick_p0');
    expect(
      params.values.contains('p0'),
      isFalse,
      reason: 'no uid in analytics',
    );
  });

  test('Like removes the Pick once the server recorded it', () async {
    await controller.load();
    await controller.like(controller.state.picks.first);
    expect(repository.decisions, [('p0', DiscoveryDecision.like)]);
    expect(uids().contains('p0'), isFalse);
    expect(analytics.names, contains(AnalyticsEvents.pickLike));
  });

  test(
    'Pass removes the Pick, and a stale reload cannot bring it back',
    () async {
      await controller.load();
      await controller.pass(controller.state.picks[1]);
      expect(uids().contains('p1'), isFalse);
      // The server has not caught up yet and still lists p1.
      repository.batch = sixPicks();
      await controller.load();
      expect(uids().contains('p1'), isFalse);
      expect(analytics.names, contains(AnalyticsEvents.pickPass));
    },
  );

  test('rapid taps send one decision', () async {
    await controller.load();
    final pick = controller.state.picks.first;
    repository.gate = Completer<void>();
    final first = controller.like(pick);
    final second = controller.like(pick);
    final third = controller.pass(pick);
    expect(controller.state.pendingUids, {'p0'});
    repository.gate!.complete();
    await Future.wait([first, second, third]);
    expect(repository.decisions, [('p0', DiscoveryDecision.like)]);
  });

  test('a failed decision keeps the Pick and surfaces an error once', () async {
    await controller.load();
    repository.failDecisions = true;
    await controller.like(controller.state.picks.first);
    expect(uids().first, 'p0');
    expect(controller.state.pendingUids, isEmpty);
    expect(controller.state.actionErrorMessage, isNotNull);
    controller.clearActionError();
    expect(controller.state.actionErrorMessage, isNull);
    // And it can be retried.
    repository.failDecisions = false;
    await controller.like(controller.state.picks.first);
    expect(uids().contains('p0'), isFalse);
  });

  test('opening a profile without deciding keeps the Pick', () async {
    await controller.load();
    controller.recordProfileOpened(controller.state.picks[2]);
    expect(uids(), ['p0', 'p1', 'p2', 'p3', 'p4', 'p5']);
    expect(repository.decisions, isEmpty);
    expect(analytics.names, contains(AnalyticsEvents.pickProfileOpen));
  });

  test('a mutual like surfaces the match for the celebration', () async {
    repository.matchOnLike = true;
    await controller.load();
    await controller.like(controller.state.picks.first);
    expect(controller.state.matchedPick?.uid, 'p0');
    expect(controller.state.matchedMatchId, 'm_p0');
    expect(analytics.names, contains(AnalyticsEvents.pickMutualMatch));
    controller.clearMatch();
    expect(controller.state.matchedPick, isNull);
  });

  test('a blocked member disappears immediately', () async {
    await controller.load();
    controller.removeImmediately('p3');
    expect(uids().contains('p3'), isFalse);
    repository.batch = sixPicks();
    await controller.load();
    expect(uids().contains('p3'), isFalse);
  });

  test(
    'deciding the last Pick lands on the "all decided" empty state',
    () async {
      repository.batch = batchOf([pickPayload(uid: 'only')]);
      await controller.load();
      await controller.pass(controller.state.picks.single);
      expect(controller.state.batch.status, PicksStatus.empty);
      expect(controller.state.batch.emptyReason, PicksEmptyReason.allDecided);
    },
  );

  test(
    'a failed first load is an error; a failed refresh keeps the cards',
    () async {
      repository.failLoads = true;
      await controller.load();
      expect(controller.state.phase, PicksPhase.error);
      repository.failLoads = false;
      await controller.load();
      expect(controller.state.phase, PicksPhase.loaded);
      repository.failLoads = true;
      await controller.load();
      expect(controller.state.phase, PicksPhase.loaded);
      expect(uids().length, 6);
    },
  );

  test('score buckets never expose the exact score', () {
    expect(PicksAnalytics.scoreBucket(93), '90_plus');
    expect(PicksAnalytics.scoreBucket(84), '80_89');
    expect(PicksAnalytics.scoreBucket(71), '70_79');
    expect(PicksAnalytics.scoreBucket(62), '60_69');
    expect(PicksAnalytics.scoreBucket(10), 'below_60');
  });
}
