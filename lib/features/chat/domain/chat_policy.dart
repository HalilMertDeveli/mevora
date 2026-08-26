import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/matching/domain/models/match.dart';

abstract final class ChatPolicy {
  static const int pageSize = 30;
  static const Duration typingDebounce = Duration(milliseconds: 400);
  static const Duration typingTtl = Duration(seconds: 3);

  static bool canSendMessage({
    required Match match,
    required String senderId,
    required String receiverId,
    required bool blocked,
  }) {
    if (!match.isActive) {
      return false;
    }
    if (blocked) {
      return false;
    }
    if (!match.isParticipant(senderId) || !match.isParticipant(receiverId)) {
      return false;
    }
    if (senderId == receiverId) {
      return false;
    }
    return true;
  }

  static bool canDeleteOwnMessage({
    required ChatMessage message,
    required String uid,
  }) {
    return message.senderId == uid && !message.deleted;
  }

  static bool canMarkRead({
    required ChatMessage message,
    required String readerUid,
  }) {
    return message.receiverId == readerUid && !message.deleted;
  }

  static MessageStatus nextStatus({
    required MessageStatus current,
    required MessageStatus incoming,
  }) {
    const order = [
      MessageStatus.sent,
      MessageStatus.delivered,
      MessageStatus.read,
    ];
    return order.indexOf(incoming) >= order.indexOf(current)
        ? incoming
        : current;
  }

  static bool isTypingFresh(DateTime? at, {DateTime? now}) {
    if (at == null) {
      return false;
    }
    final current = now ?? DateTime.now();
    return current.difference(at) <= typingTtl;
  }
}
