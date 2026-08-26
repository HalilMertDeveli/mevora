import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/match_score_scope.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/match_score/data/datasources/memory_match_score_data_source.dart';
import 'package:mevora/features/match_score/data/repositories/match_score_repository_impl.dart';
import 'package:mevora/features/match_score/domain/services/match_feedback_filter.dart';
import 'package:mevora/features/match_score/domain/services/match_score_policy.dart';
import 'package:mevora/features/match_score/presentation/widgets/match_score_tile.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/l10n/app_localizations.dart';

class _Uid implements AuthUidSource {
  _Uid(this.currentUid);
  @override
  final String currentUid;
  @override
  Stream<String?> watchUid() => Stream.value(currentUid);
}

void main() {
  test('new users start at 50 match points', () {
    final source = MemoryMatchScoreDataSource();
    source.ensureUser('aya');
    expect(source.scoreOf('aya'), MatchScorePolicy.initialScore);
    expect(MatchScorePolicy.seed(null), 50);
  });

  test('unique mutual match awards +1 to both, once', () {
    DateTime clock() => DateTime.utc(2026, 8, 20, 12);
    final graph = InMemorySocialGraph(
      now: clock,
      matchScore: MemoryMatchScoreDataSource(clock: clock),
    );
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    expect(graph.matchScore.scoreOf('aya'), 50);
    expect(graph.matchScore.scoreOf('can'), 50);

    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');

    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);
    graph.matchScore.recordMatchCreated(
      matchId: 'aya_can',
      userIds: const ['aya', 'can'],
      matchedAt: clock(),
    );
    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);
  });

  test('two-way messaging in the window awards +1 once; spam still 1', () {
    final now = DateTime.utc(2026, 8, 20, 12);
    final graph = InMemorySocialGraph(
      now: () => now,
      matchScore: MemoryMatchScoreDataSource(clock: () => now),
    );
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');

    graph.sendText(
      actorUid: 'aya',
      matchId: 'aya_can',
      receiverId: 'can',
      text: 'Merhaba',
    );
    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);

    graph.sendText(
      actorUid: 'can',
      matchId: 'aya_can',
      receiverId: 'aya',
      text: 'Selam',
    );
    expect(graph.matchScore.scoreOf('aya'), 52);
    expect(graph.matchScore.scoreOf('can'), 52);

    for (var i = 0; i < 50; i++) {
      graph.sendText(
        actorUid: i.isEven ? 'aya' : 'can',
        matchId: 'aya_can',
        receiverId: i.isEven ? 'can' : 'aya',
        text: 'spam $i',
      );
    }
    expect(graph.matchScore.scoreOf('aya'), 52);
    expect(graph.matchScore.scoreOf('can'), 52);
  });

  test('after 3 days messages still work but no interaction bonus', () {
    var now = DateTime.utc(2026, 8, 20, 12);
    final graph = InMemorySocialGraph(
      now: () => now,
      matchScore: MemoryMatchScoreDataSource(clock: () => now),
    );
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    graph.sendText(
      actorUid: 'aya',
      matchId: 'aya_can',
      receiverId: 'can',
      text: 'Hi',
    );

    now = now.add(const Duration(days: 3, minutes: 1));
    graph.sendText(
      actorUid: 'can',
      matchId: 'aya_can',
      receiverId: 'aya',
      text: 'Hey',
    );
    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);
  });

  test('unmatch keeps scores and lets the other person leave private feedback', () async {
    final graph = InMemorySocialGraph(now: () => DateTime.utc(2026, 8, 20, 12));
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    graph.unmatch(actorUid: 'aya', matchId: 'aya_can');

    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);

    final repo = MatchScoreRepositoryImpl(
      dataSource: graph.matchScore,
      uidSource: _Uid('can'),
    );
    final pending = await repo.watchPendingFeedback('can').first;
    expect(pending.single.matchId, 'aya_can');

    final ayaRepo = MatchScoreRepositoryImpl(
      dataSource: graph.matchScore,
      uidSource: _Uid('aya'),
    );
    expect((await ayaRepo.watchPendingFeedback('aya').first), isEmpty);

    final result = await repo.submitFeedback(
      matchId: 'aya_can',
      text: 'Nice chat, not a fit',
    );
    expect(result.isSuccess, isTrue);
    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);
    expect(graph.matchScore.feedbackOf('can', 'aya_can')?.text, isNotEmpty);
    expect(graph.matchScore.feedbackOf('aya', 'aya_can'), isNull);
  });

  test('block keeps scores and offers feedback to the remaining user', () async {
    final graph = InMemorySocialGraph(now: () => DateTime.utc(2026, 8, 20, 12));
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    graph.blockUser(actorUid: 'can', userId: 'aya');

    expect(graph.matchScore.scoreOf('aya'), 51);
    expect(graph.matchScore.scoreOf('can'), 51);

    final repo = MatchScoreRepositoryImpl(
      dataSource: graph.matchScore,
      uidSource: _Uid('aya'),
    );
    final pending = await repo.watchPendingFeedback('aya').first;
    expect(pending.single.endedReason, 'block');
    final skipped = await repo.dismissFeedback(matchId: 'aya_can');
    expect(skipped.isSuccess, isTrue);
    expect(graph.matchScore.scoreOf('aya'), 51);
  });

  test('feedback filter strips insults and PII', () {
    final cleaned = MatchFeedbackFilter.sanitize(
      'salak call me at +905551112233 or ada@email.com',
    );
    expect(cleaned.contains('salak'), isFalse);
    expect(cleaned.contains('ada@email.com'), isFalse);
    expect(cleaned.contains('555'), isFalse);
    expect(cleaned.contains('***'), isTrue);
  });

  testWidgets('own profile shows match points', (tester) async {
    final source = MemoryMatchScoreDataSource();
    source.ensureUser('aya');
    source.recordMatchCreated(
      matchId: 'aya_can',
      userIds: const ['aya', 'can'],
      matchedAt: DateTime.utc(2026, 8, 20),
    );
    final repo = MatchScoreRepositoryImpl(
      dataSource: source,
      uidSource: _Uid('aya'),
    );
    await tester.pumpWidget(
      MatchScoreScope(
        repository: repo,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: MatchScoreTile(uid: 'aya', repository: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Match points'), findsOneWidget);
    expect(find.text('51 points'), findsOneWidget);
  });
}
