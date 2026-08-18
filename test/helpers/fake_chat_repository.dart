import 'dart:async';

import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.uid = 'user-1'});

  final String uid;
  final Map<String, List<ChatMessage>> messages = {};
  final Map<String, Map<String, DateTime>> typing = {};
  final _messageControllers = <String, StreamController<List<ChatMessage>>>{};
  final _typingControllers =
      <String, StreamController<Map<String, DateTime>>>{};
  int _seq = 0;

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    return _messagesController(matchId).stream;
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) async {
    final all = messages[matchId] ?? const <ChatMessage>[];
    final older = all
        .where((item) => item.createdAt.isBefore(before.createdAt))
        .toList();
    final page = older.length > limit
        ? older.sublist(older.length - limit)
        : older;
    return ChatPage(messages: page, hasMore: older.length > limit);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) async {
    _seq += 1;
    final message = ChatMessage(
      id: 'msg-$_seq',
      senderId: uid,
      receiverId: receiverId,
      text: text,
      type: MessageType.text,
      createdAt: DateTime.utc(2026, 8, 18, 12, _seq),
      status: MessageStatus.sent,
    );
    messages.putIfAbsent(matchId, () => []).add(message);
    _messagesController(matchId).add(List<ChatMessage>.from(messages[matchId]!));
    return message;
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> items) async {}

  @override
  Future<void> markRead(String matchId, List<ChatMessage> items) async {
    final current = messages[matchId];
    if (current == null) {
      return;
    }
    final ids = items.map((item) => item.id).toSet();
    messages[matchId] = [
      for (final item in current)
        if (ids.contains(item.id))
          item.copyWith(
            status: MessageStatus.read,
            isRead: true,
            readAt: DateTime.utc(2026, 8, 18, 13),
          )
        else
          item,
    ];
    _messagesController(matchId).add(List<ChatMessage>.from(messages[matchId]!));
  }

  @override
  Future<void> setTyping({
    required String matchId,
    required bool isTyping,
  }) async {
    final map = typing.putIfAbsent(matchId, () => {});
    if (isTyping) {
      map[uid] = DateTime.utc(2026, 8, 18, 12);
    } else {
      map.remove(uid);
    }
    _typingController(matchId).add(Map<String, DateTime>.from(map));
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return _typingController(matchId).stream;
  }

  StreamController<List<ChatMessage>> _messagesController(String matchId) {
    return _messageControllers.putIfAbsent(
      matchId,
      () => StreamController<List<ChatMessage>>.broadcast(
        onListen: () {
          _messageControllers[matchId]?.add(
            List<ChatMessage>.from(messages[matchId] ?? const []),
          );
        },
      ),
    );
  }

  StreamController<Map<String, DateTime>> _typingController(String matchId) {
    return _typingControllers.putIfAbsent(
      matchId,
      () => StreamController<Map<String, DateTime>>.broadcast(
        onListen: () {
          _typingControllers[matchId]?.add(
            Map<String, DateTime>.from(typing[matchId] ?? const {}),
          );
        },
      ),
    );
  }

  void dispose() {
    for (final controller in _messageControllers.values) {
      unawaited(controller.close());
    }
    for (final controller in _typingControllers.values) {
      unawaited(controller.close());
    }
  }
}
