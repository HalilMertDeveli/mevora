import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/storage/storage_provider.dart';
import 'package:mevora/features/chat/data/datasources/firebase_chat_data_source.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required FirebaseChatDataSource dataSource,
    StorageProvider? storage,
  }) : _dataSource = dataSource,
       _storage = storage;

  final FirebaseChatDataSource _dataSource;
  final StorageProvider? _storage;

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    return _dataSource.watchLatest(matchId, limit: limit);
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) {
    return _dataSource.loadOlder(
      matchId: matchId,
      before: before,
      limit: limit,
    );
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) {
    return _dataSource.sendText(
      matchId: matchId,
      receiverId: receiverId,
      text: text,
    );
  }

  @override
  Future<ChatMessage> sendImage({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    return _sendUploaded(
      matchId: matchId,
      receiverId: receiverId,
      media: media,
      type: MessageType.image,
      onProgress: onProgress,
    );
  }

  @override
  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    return _sendUploaded(
      matchId: matchId,
      receiverId: receiverId,
      media: media,
      type: MessageType.voice,
      onProgress: onProgress,
    );
  }

  Future<ChatMessage> _sendUploaded({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    required MessageType type,
    void Function(double progress)? onProgress,
  }) async {
    final storage = _storage;
    if (storage == null) {
      throw StateError('Chat storage is not configured');
    }
    final ownerUid = _dataSource.currentUid;
    if (ownerUid == null) {
      throw StateError('unauthenticated');
    }
    final messageId = _dataSource.allocateMessageId(matchId);
    final extension = type == MessageType.voice
        ? _voiceExtension(media.contentType)
        : _imageExtension(media.contentType);
    final path = type == MessageType.voice
        ? StoragePaths.chatVoice(
            ownerUid: ownerUid,
            matchId: matchId,
            messageId: messageId,
            extension: extension,
          )
        : StoragePaths.chatImage(
            ownerUid: ownerUid,
            matchId: matchId,
            messageId: messageId,
            extension: extension,
          );
    final uploaded = await storage.uploadBytes(
      path: path,
      bytes: media.bytes,
      contentType: media.contentType,
      onProgress: onProgress,
    );
    switch (uploaded) {
      case Err(:final failure):
        throw failure;
      case Success(:final value):
        return _dataSource.sendMediaMessage(
          matchId: matchId,
          receiverId: receiverId,
          type: type,
          messageId: messageId,
          imageStoragePath: type == MessageType.image ? path : null,
          voiceStoragePath: type == MessageType.voice ? path : null,
          mediaUrl: value.toString(),
          durationMs: media.durationMs,
        );
    }
  }

  static String _imageExtension(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('png')) {
      return 'png';
    }
    if (lower.contains('webp')) {
      return 'webp';
    }
    return 'jpg';
  }

  static String _voiceExtension(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('mpeg') || lower.contains('mp3')) {
      return 'mp3';
    }
    if (lower.contains('wav')) {
      return 'wav';
    }
    if (lower.contains('aac')) {
      return 'aac';
    }
    return 'm4a';
  }

  @override
  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  }) {
    return _dataSource.deleteMessage(matchId: matchId, messageId: messageId);
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) {
    return _dataSource.markDelivered(matchId, messages);
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) {
    return _dataSource.markRead(matchId, messages);
  }

  @override
  Future<void> setTyping({required String matchId, required bool isTyping}) {
    return _dataSource.setTyping(matchId: matchId, isTyping: isTyping);
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return _dataSource.watchTyping(matchId);
  }
}
