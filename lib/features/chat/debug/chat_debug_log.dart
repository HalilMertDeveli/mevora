import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';

/// Debug-only chat telemetry. Never logs plaintext message content.
class ChatDebugLog {
  static void event(String message, {Map<String, Object?>? fields}) {
    if (!kDebugMode) {
      return;
    }
    final buffer = StringBuffer(message);
    fields?.forEach((key, value) {
      buffer.write(' $key=$value');
    });
    developer.log(buffer.toString(), name: 'CHAT');
  }

  static void messageSnapshot({
    required String action,
    required String matchId,
    required ChatMessage message,
  }) {
    if (!kDebugMode) {
      return;
    }
    event(
      action,
      fields: {
        'matchId': matchId,
        'messageId': message.id,
        'senderId': message.senderId,
        'receiverId': message.receiverId,
        'type': message.type.name,
        'status': message.status.name,
        'encrypted': message.isEncrypted,
        'decryptFailed': message.decryptFailed,
        'createdAt': message.createdAt.toIso8601String(),
        if (message.durationMs != null) 'durationMs': message.durationMs,
      },
    );
  }
}
