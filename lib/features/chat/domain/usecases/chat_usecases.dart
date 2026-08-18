import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/domain/models/match.dart';

class SendChatText {
  const SendChatText(this._chat);

  final ChatRepository _chat;

  Future<Result<ChatMessage>> call({
    required Match match,
    required String senderId,
    required String receiverId,
    required String text,
    required bool blocked,
  }) async {
    if (!ChatPolicy.canSendMessage(
      match: match,
      senderId: senderId,
      receiverId: receiverId,
      blocked: blocked,
    )) {
      return const Err<ChatMessage>(
        AuthzFailure('This conversation is not available.'),
      );
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const Err<ChatMessage>(
        ValidationFailure('Message cannot be empty'),
      );
    }
    try {
      final message = await _chat.sendText(
        matchId: match.id,
        receiverId: receiverId,
        text: trimmed,
      );
      return Success(message);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}

class MarkChatRead {
  const MarkChatRead(this._chat);

  final ChatRepository _chat;

  Future<Result<void>> call({
    required String matchId,
    required String readerUid,
    required List<ChatMessage> messages,
  }) async {
    final incoming = messages
        .where(
          (message) => ChatPolicy.canMarkRead(
            message: message,
            readerUid: readerUid,
          ),
        )
        .toList(growable: false);
    if (incoming.isEmpty) {
      return const Success(null);
    }
    try {
      await _chat.markDelivered(matchId, incoming);
      await _chat.markRead(matchId, incoming);
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}

class SetChatTyping {
  const SetChatTyping(this._chat);

  final ChatRepository _chat;

  Future<Result<void>> call({
    required String matchId,
    required bool isTyping,
  }) async {
    try {
      await _chat.setTyping(matchId: matchId, isTyping: isTyping);
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}
