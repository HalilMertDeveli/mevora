import 'package:mevora/features/chat/domain/models/chat_message.dart';

/// Pagination DTO. Distinct from the `ChatPage` widget — import one library
/// at a time, or prefix.
class ChatPage {
  const ChatPage({
    required this.messages,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatMediaBytes {
  const ChatMediaBytes({
    required this.bytes,
    required this.contentType,
    this.durationMs,
  });

  final List<int> bytes;
  final String contentType;
  final int? durationMs;
}

abstract class ChatRepository {
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30});

  Future<bool> isE2eeActive({
    required String matchId,
    required String peerUid,
  });

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

  Future<ChatMessage> sendImage({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  });

  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  });

  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  });

  Future<void> markDelivered(String matchId, List<ChatMessage> messages);

  Future<void> markRead(String matchId, List<ChatMessage> messages);

  Future<void> setTyping({
    required String matchId,
    required bool isTyping,
  });

  Stream<Map<String, DateTime>> watchTyping(String matchId);
}
