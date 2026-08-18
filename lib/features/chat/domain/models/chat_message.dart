enum MessageType { text, image, gif, voice, system }

enum MessageStatus { sent, delivered, read }

extension MessageTypeX on MessageType {
  String get firestoreValue => name;

  static MessageType fromFirestore(String? value) {
    return MessageType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => MessageType.text,
    );
  }
}

extension MessageStatusX on MessageStatus {
  String get firestoreValue => name;

  static MessageStatus fromFirestore(String? value) {
    return MessageStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => MessageStatus.sent,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.type,
    required this.createdAt,
    required this.status,
    this.isRead = false,
    this.readAt,
    this.imageStoragePath,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final MessageType type;
  final DateTime createdAt;
  final MessageStatus status;
  final bool isRead;
  final DateTime? readAt;

  /// Architecture-only for type=image. No send UI yet.
  final String? imageStoragePath;

  bool get isMine => false;

  bool isFrom(String uid) => senderId == uid;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? text,
    MessageType? type,
    DateTime? createdAt,
    MessageStatus? status,
    bool? isRead,
    DateTime? readAt,
    String? imageStoragePath,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
    );
  }
}

/// Storage contract for a future image composer. Not used by UI.
abstract final class ImageMessageArchitecture {
  static String storagePath({
    required String senderUid,
    required String matchId,
    required String messageId,
  }) {
    return 'users/$senderUid/chat/$matchId/$messageId';
  }
}
