import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/presentation/pages/matches_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';

class _Uid implements AuthUidSource {
  _Uid(this.currentUid);

  @override
  String? currentUid;

  @override
  Stream<String?> watchUid() => const Stream.empty();
}

/// Counts every listener opened, which is what a resume used to multiply.
class _CountingMatches implements MatchRepository {
  final List<int?> limits = [];
  final List<StreamController<List<MatchListItem>>> streams = [];

  StreamController<List<MatchListItem>> get latest => streams.last;

  @override
  Stream<List<MatchListItem>> watchMatches(String uid, {int? limit}) {
    limits.add(limit);
    final controller = StreamController<List<MatchListItem>>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<Match?> getMatch(String matchId) async => null;

  @override
  Stream<Match?> watchMatch(String matchId) => const Stream.empty();

  @override
  Future<void> markOpened(String matchId, String uid) async {}
}

class _CountingPresence implements PresenceRepository {
  final Map<String, int> opened = {};
  final Map<String, StreamController<PresenceWatch>> streams = {};

  @override
  Stream<PresenceWatch> watch(String uid) {
    opened[uid] = (opened[uid] ?? 0) + 1;
    final controller = StreamController<PresenceWatch>();
    streams[uid] = controller;
    return controller.stream;
  }

  @override
  Future<void> setOnline(String uid) async {}

  @override
  Future<void> setOffline(String uid) async {}

  @override
  Future<void> heartbeat(String uid) async {}
}

List<MatchListItem> _items(int count) {
  return [
    for (var i = 0; i < count; i++)
      MatchListItem(
        match: Match(
          id: 'm$i',
          userIds: ['me', 'u$i'],
          createdAt: DateTime.utc(2026, 9, 1),
          isActive: true,
        ),
        otherUserId: 'u$i',
        name: 'User $i',
      ),
  ];
}

void main() {
  late _Uid uid;
  late _CountingMatches matches;
  late _CountingPresence presence;
  late MatchesController controller;

  setUp(() {
    uid = _Uid('me');
    matches = _CountingMatches();
    presence = _CountingPresence();
    controller = MatchesController(
      matchRepository: matches,
      presenceRepository: presence,
      uidSource: uid,
    );
  });

  tearDown(() => controller.dispose());

  test('start listens to one page, not every match', () async {
    controller.start();
    expect(matches.limits, [MatchesController.pageSize]);
  });

  test('resume keeps healthy inbox and presence listeners', () async {
    controller.start();
    matches.latest.add(_items(3));
    await pumpEventQueue();
    expect(presence.opened, {'u0': 1, 'u1': 1, 'u2': 1});

    controller.resume();
    controller.resume();
    await pumpEventQueue();

    expect(matches.limits, hasLength(1));
    expect(presence.opened, {'u0': 1, 'u1': 1, 'u2': 1});
  });

  test('resume restarts an inbox listener that failed', () async {
    controller.start();
    matches.latest.addError(StateError('permission-denied'));
    await pumpEventQueue();
    expect(controller.error, isNotNull);

    controller.resume();
    matches.latest.add(_items(1));
    await pumpEventQueue();

    expect(matches.limits, hasLength(2));
    expect(controller.error, isNull);
    expect(controller.items, hasLength(1));
  });

  test('resume restarts when the signed-in user changed', () async {
    controller.start();
    uid.currentUid = 'someone-else';
    controller.resume();
    expect(matches.limits, hasLength(2));
  });

  test('resume reopens only the presence listener that failed', () async {
    controller.start();
    matches.latest.add(_items(2));
    await pumpEventQueue();

    presence.streams['u1']!.addError(StateError('unavailable'));
    await pumpEventQueue();
    controller.resume();
    await pumpEventQueue();

    expect(presence.opened, {'u0': 1, 'u1': 2});
  });

  test('loadMore widens the window only when the page is full', () async {
    controller.start();
    matches.latest.add(_items(MatchesController.pageSize - 1));
    await pumpEventQueue();
    expect(controller.hasMore, isFalse);
    controller.loadMore();
    expect(matches.limits, hasLength(1));

    matches.latest.add(_items(MatchesController.pageSize));
    await pumpEventQueue();
    expect(controller.hasMore, isTrue);

    controller.loadMore();
    // A second trigger before the wider snapshot lands is a no-op.
    controller.loadMore();
    expect(matches.limits, [
      MatchesController.pageSize,
      MatchesController.pageSize * 2,
    ]);
    expect(matches.streams.first.hasListener, isFalse);

    matches.latest.add(_items(MatchesController.pageSize + 4));
    await pumpEventQueue();
    expect(controller.items, hasLength(MatchesController.pageSize + 4));
    expect(controller.hasMore, isFalse);
    // Widening the window keeps the presence listeners already open.
    expect(presence.opened['u0'], 1);
  });

  testWidgets('scrolling to the end of the inbox loads the next page', (
    tester,
  ) async {
    final graph = InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12));
    graph.seedProfile('aya', name: 'Ayşe');
    const total = MatchesController.pageSize + 5;
    for (var i = 0; i < total; i++) {
      graph.seedProfile('p$i', name: 'Person $i');
      graph.recordSwipe(actorUid: 'aya', targetUserId: 'p$i', action: 'like');
      graph.recordSwipe(actorUid: 'p$i', targetUserId: 'aya', action: 'like');
    }
    final services = createGraphSocialServices(
      graph: graph,
      uidSource: MutableAuthUidSource('aya'),
    );
    late MatchesController inbox;
    await tester.pumpWidget(
      SocialScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('tr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              inbox = SocialScope.of(context).matchesController;
              return MatchesPage(controller: inbox);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(inbox.items, hasLength(MatchesController.pageSize));
    expect(inbox.hasMore, isTrue);

    await tester.dragUntilVisible(
      find.byType(CircularProgressIndicator),
      find.byType(ListView),
      const Offset(0, -600),
    );
    await tester.pump();
    await tester.pump();

    expect(inbox.items, hasLength(total));
    expect(inbox.hasMore, isFalse);
  });
}
