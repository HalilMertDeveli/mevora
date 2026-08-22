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
    this.deleted = false,
    this.imageStoragePath,
    this.voiceStoragePath,
    this.mediaUrl,
    this.durationMs,
    this.localMediaBytes,
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
  final bool deleted;

  /// Storage object for type=image. Participants read via Storage rules.
  final String? imageStoragePath;

  /// Storage object for type=voice.
  final String? voiceStoragePath;

  /// Download URL written after upload. Never contains message body PII.
  final String? mediaUrl;

  /// Voice duration in milliseconds.
  final int? durationMs;

  /// In-memory demo/preview bytes. Never written to Firestore.
  final List<int>? localMediaBytes;

  bool get isMine => false;

  bool isFrom(String uid) => senderId == uid;

  String? get storagePath => switch (type) {
        MessageType.image => imageStoragePath,
        MessageType.voice => voiceStoragePath,
        _ => imageStoragePath ?? voiceStoragePath,
      };

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
    bool? deleted,
    String? imageStoragePath,
    String? voiceStoragePath,
    String? mediaUrl,
    int? durationMs,
    List<int>? localMediaBytes,
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
      deleted: deleted ?? this.deleted,
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
      voiceStoragePath: voiceStoragePath ?? this.voiceStoragePath,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      durationMs: durationMs ?? this.durationMs,
      localMediaBytes: localMediaBytes ?? this.localMediaBytes,
    );
  }
}

/// Storage contract for chat media. Path owner is always the sender UID.
abstract final class ChatMediaArchitecture {
  static String storagePath({
    required String senderUid,
    required String matchId,
    required String messageId,
    String? extension,
  }) {
    final suffix = (extension == null || extension.isEmpty) ? '' : '.$extension';
    return 'users/$senderUid/chat/$matchId/$messageId$suffix';
  }
}

/// @deprecated Use [ChatMediaArchitecture]. Kept for existing imports.
abstract final class ImageMessageArchitecture {
  static String storagePath({
    required String senderUid,
    required String matchId,
    required String messageId,
  }) {
    return ChatMediaArchitecture.storagePath(
      senderUid: senderUid,
      matchId: matchId,
      messageId: messageId,
    );
  }
}
