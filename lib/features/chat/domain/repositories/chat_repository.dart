import 'package:mevora/features/chat/domain/models/chat_message.dart';

class ChatPage {
  const ChatPage({
    required this.messages,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
}

abstract class ChatRepository {
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30});

  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  });

  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  });

  Future<void> markDelivered(String matchId, List<ChatMessage> messages);

  Future<void> markRead(String matchId, List<ChatMessage> messages);

  Future<void> setTyping({
    required String matchId,
    required bool isTyping,
  });

  Stream<Map<String, DateTime>> watchTyping(String matchId);
}
