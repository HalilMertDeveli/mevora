import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';

void main() {
  final match = MatchEngine.buildMatch(
    uidA: 'a',
    uidB: 'b',
    createdAt: DateTime(2026),
  );

  test('only active unblocked participants can send', () {
    expect(
      ChatPolicy.canSendMessage(
        match: match,
        senderId: 'a',
        receiverId: 'b',
        blocked: false,
      ),
      isTrue,
    );
    expect(
      ChatPolicy.canSendMessage(
        match: match.copyWith(isActive: false),
        senderId: 'a',
        receiverId: 'b',
        blocked: false,
      ),
      isFalse,
    );
    expect(
      ChatPolicy.canSendMessage(
        match: match,
        senderId: 'a',
        receiverId: 'b',
        blocked: true,
      ),
      isFalse,
    );
  });

  test('receiver can mark read and status only moves forward', () {
    final message = ChatMessage(
      id: '1',
      senderId: 'a',
      receiverId: 'b',
      text: 'hi',
      type: MessageType.text,
      createdAt: DateTime(2026),
      status: MessageStatus.sent,
    );
    expect(ChatPolicy.canMarkRead(message: message, readerUid: 'b'), isTrue);
    expect(ChatPolicy.canMarkRead(message: message, readerUid: 'a'), isFalse);
    expect(
      ChatPolicy.nextStatus(
        current: MessageStatus.delivered,
        incoming: MessageStatus.sent,
      ),
      MessageStatus.delivered,
    );
    expect(
      ChatPolicy.nextStatus(
        current: MessageStatus.sent,
        incoming: MessageStatus.read,
      ),
      MessageStatus.read,
    );
  });

  test('only the sender can delete their own message', () {
    final message = ChatMessage(
      id: '1',
      senderId: 'a',
      receiverId: 'b',
      text: 'hi',
      type: MessageType.text,
      createdAt: DateTime(2026),
      status: MessageStatus.sent,
    );
    expect(
      ChatPolicy.canDeleteOwnMessage(message: message, uid: 'a'),
      isTrue,
    );
    expect(
      ChatPolicy.canDeleteOwnMessage(message: message, uid: 'b'),
      isFalse,
    );
    expect(
      ChatPolicy.canDeleteOwnMessage(
        message: message.copyWith(deleted: true),
        uid: 'a',
      ),
      isFalse,
    );
  });

  test('typing freshness uses a short ttl', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(
      ChatPolicy.isTypingFresh(
        now.subtract(const Duration(seconds: 2)),
        now: now,
      ),
      isTrue,
    );
    expect(
      ChatPolicy.isTypingFresh(
        now.subtract(const Duration(seconds: 5)),
        now: now,
      ),
      isFalse,
    );
  });
}
