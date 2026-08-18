import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

void main() {
  late InMemorySocialGraph graph;

  setUp(() {
    graph = InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12));
    graph.seedProfile('aya', name: 'Ayşe');
    graph.seedProfile('can', name: 'Can');
  });

  test('like-like creates a single canonical match', () {
    final first = graph.recordSwipe(
      actorUid: 'aya',
      targetUserId: 'can',
      action: 'like',
    );
    expect(first.matched, isFalse);
    final second = graph.recordSwipe(
      actorUid: 'can',
      targetUserId: 'aya',
      action: 'like',
    );
    expect(second.matched, isTrue);
    expect(second.match?.id, 'aya_can');
    expect(second.match?.userIds, ['aya', 'can']);
    expect(graph.matches.length, 1);
  });

  test('client-equivalent duplicate like is rejected', () {
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    expect(
      () => graph.recordSwipe(
        actorUid: 'aya',
        targetUserId: 'can',
        action: 'like',
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('chat send, unread, and receipts', () {
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    final message = graph.sendText(
      actorUid: 'aya',
      matchId: 'aya_can',
      receiverId: 'can',
      text: 'Merhaba',
    );
    expect(graph.matches['aya_can']!.unreadFor('can'), 1);
    expect(message.status, MessageStatus.sent);
    graph.markRead(
      actorUid: 'can',
      matchId: 'aya_can',
      items: graph.latestMessages('aya_can'),
    );
    expect(graph.matches['aya_can']!.unreadFor('can'), 0);
    expect(graph.latestMessages('aya_can').first.isRead, isTrue);
  });

  test('unmatch disables new messages', () {
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    graph.unmatch(actorUid: 'aya', matchId: 'aya_can');
    expect(graph.matches['aya_can']!.isActive, isFalse);
    expect(
      () => graph.sendText(
        actorUid: 'aya',
        matchId: 'aya_can',
        receiverId: 'can',
        text: 'hi',
      ),
      throwsA(isA<AuthzException>()),
    );
  });

  test('block disables chat, match, and calls', () {
    graph.recordSwipe(actorUid: 'aya', targetUserId: 'can', action: 'like');
    graph.recordSwipe(actorUid: 'can', targetUserId: 'aya', action: 'like');
    graph.blockUser(actorUid: 'aya', userId: 'can');
    expect(
      SafetyPolicy.isBlocked(blockIds: graph.blockIds, uidA: 'aya', uidB: 'can'),
      isTrue,
    );
    expect(graph.matches['aya_can']!.isActive, isFalse);
    expect(
      () => graph.recordSwipe(
        actorUid: 'can',
        targetUserId: 'aya',
        action: 'like',
      ),
      throwsA(isA<AuthzException>()),
    );
    expect(
      () => graph.createCall(
        actorUid: 'aya',
        matchId: 'aya_can',
        receiverId: 'can',
      ),
      throwsA(isA<AuthzException>()),
    );
  });

  test('report stores admin-ready open status', () {
    graph.report(
      actorUid: 'aya',
      userId: 'can',
      reason: 'spam',
      matchId: 'aya_can',
    );
    expect(graph.reports.single.status, 'open');
    expect(graph.reports.single.reporterId, 'aya');
  });
}
