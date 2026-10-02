import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

/// Records every write the controller makes. The message stream is driven
/// by the test, so a snapshot can be replayed the way Firestore replays a
/// document after a local receipt write.
class _RecordingChat implements ChatRepository {
  final snapshots = StreamController<List<ChatMessage>>.broadcast();
  final List<List<String>> readBatches = [];
  final List<bool> typingWrites = [];
  int deliveredBatches = 0;
  int failReads = 0;
  int _seq = 0;

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) =>
      snapshots.stream;

  @override
  Future<bool> isE2eeActive({
    required String matchId,
    required String peerUid,
  }) async => false;

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) async => const ChatPage(messages: [], hasMore: false);

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) async {
    _seq += 1;
    return ChatMessage(
      id: 'sent-$_seq',
      senderId: 'a',
      receiverId: receiverId,
      text: text,
      type: MessageType.text,
      createdAt: DateTime.utc(2026, 9, 30, 12, _seq),
      status: MessageStatus.sent,
    );
  }

  @override
  Future<ChatMessage> sendImage({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  }) async {}

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) async {
    deliveredBatches += 1;
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) async {
    if (failReads > 0) {
      failReads -= 1;
      throw StateError('unavailable');
    }
    readBatches.add([for (final message in messages) message.id]);
  }

  @override
  Future<void> setTyping({
    required String matchId,
    required bool isTyping,
  }) async {
    typingWrites.add(isTyping);
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) =>
      const Stream.empty();
}

class _CountingMatches implements MatchRepository {
  _CountingMatches(this._inner);

  final MatchRepository _inner;
  int opened = 0;

  // The optional limit keeps this override valid whether or not the
  // repository interface declares it.
  @override
  Stream<List<MatchListItem>> watchMatches(String uid, {int? limit}) =>
      _inner.watchMatches(uid);

  @override
  Future<Match?> getMatch(String matchId) => _inner.getMatch(matchId);

  @override
  Stream<Match?> watchMatch(String matchId) => _inner.watchMatch(matchId);

  @override
  Future<void> markOpened(String matchId, String uid) {
    opened += 1;
    return _inner.markOpened(matchId, uid);
  }
}

ChatMessage _incoming(String id, {bool isRead = false}) {
  return ChatMessage(
    id: id,
    senderId: 'b',
    receiverId: 'a',
    text: id,
    type: MessageType.text,
    createdAt: DateTime.utc(2026, 9, 30, 12),
    status: isRead ? MessageStatus.read : MessageStatus.sent,
    isRead: isRead,
  );
}

void main() {
  late InMemorySocialGraph graph;
  late _RecordingChat chat;
  late _CountingMatches matches;
  late String matchId;

  ChatController controllerFor() {
    final auth = MutableAuthUidSource('a');
    final services = createGraphSocialServices(graph: graph, uidSource: auth);
    final controller = ChatController(
      matchId: matchId,
      chatRepository: chat,
      matchRepository: matches,
      safetyRepository: services.safetyRepository,
      presenceRepository: services.presenceRepository,
      uidSource: auth,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    graph = InMemorySocialGraph(now: () => DateTime.utc(2026, 9, 30, 12));
    graph.seedProfile('a', name: 'Ada');
    graph.seedProfile('b', name: 'Bea');
    graph.recordSwipe(actorUid: 'a', targetUserId: 'b', action: 'like');
    graph.recordSwipe(actorUid: 'b', targetUserId: 'a', action: 'like');
    matchId = graph.matches.keys.single;
    chat = _RecordingChat();
    final auth = MutableAuthUidSource('a');
    matches = _CountingMatches(
      createGraphSocialServices(graph: graph, uidSource: auth).matchRepository,
    );
  });

  test(
    'an incoming message gets one read receipt, never a delivered one',
    () async {
      final controller = controllerFor();
      await controller.start();

      chat.snapshots.add([_incoming('m1')]);
      await pumpEventQueue();
      // The receipt write's own local snapshot, still showing m1 unread.
      chat.snapshots.add([_incoming('m1')]);
      await pumpEventQueue();
      chat.snapshots.add([_incoming('m1', isRead: true), _incoming('m2')]);
      await pumpEventQueue();

      expect(chat.readBatches, [
        ['m1'],
        ['m2'],
      ]);
      expect(chat.deliveredBatches, 0);
    },
  );

  test('a failed receipt is retried on the next snapshot', () async {
    final controller = controllerFor();
    await controller.start();
    chat.failReads = 1;

    chat.snapshots.add([_incoming('m1')]);
    await pumpEventQueue();
    expect(chat.readBatches, isEmpty);

    chat.snapshots.add([_incoming('m1')]);
    await pumpEventQueue();
    expect(chat.readBatches, [
      ['m1'],
    ]);
  });

  test('sending without typing writes no typing flag', () async {
    final controller = controllerFor();
    await controller.start();

    await controller.send('hi');
    await controller.send('again');

    expect(chat.typingWrites, isEmpty);
  });

  test('sending clears a typing flag once and cancels a pending one', () async {
    final controller = controllerFor();
    await controller.start();

    controller.onComposerChanged('hel');
    await Future<void>.delayed(
      ChatPolicy.typingDebounce + const Duration(milliseconds: 20),
    );
    expect(chat.typingWrites, [true]);

    await controller.send('hello');
    expect(chat.typingWrites, [true, false]);

    // Typed and sent inside the debounce window: no flag after the send.
    controller.onComposerChanged('x');
    await controller.send('x');
    await Future<void>.delayed(
      ChatPolicy.typingDebounce + const Duration(milliseconds: 20),
    );
    expect(chat.typingWrites, [true, false]);
  });

  test('opening an already-read thread does not rewrite the match', () async {
    await controllerFor().start();
    expect(matches.opened, 1, reason: 'a new match is marked opened once');

    await controllerFor().start();
    expect(matches.opened, 1);
  });
}
