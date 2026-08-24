import 'dart:typed_data';

import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/storage/storage_provider.dart';
import 'package:mevora/features/chat/data/datasources/firebase_chat_data_source.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_chat_service.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required FirebaseChatDataSource dataSource,
    StorageProvider? storage,
    E2eeChatService? e2ee,
    AuthUidSource? uidSource,
  }) : _dataSource = dataSource,
       _storage = storage,
       _e2ee = e2ee,
       _uidSource = uidSource;

  final FirebaseChatDataSource _dataSource;
  final StorageProvider? _storage;
  final E2eeChatService? _e2ee;
  final AuthUidSource? _uidSource;

  bool get _e2eeEnabled => _e2ee != null && _uidSource?.currentUid != null;

  @override
  Future<bool> isE2eeActive({
    required String matchId,
    required String peerUid,
  }) async {
    if (!_e2eeEnabled) {
      return false;
    }
    final uid = _uidSource!.currentUid!;
    return _e2ee!.isSessionReady(uid: uid, matchId: matchId, peerUid: peerUid);
  }

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    final raw = _dataSource.watchLatest(matchId, limit: limit);
    if (!_e2eeEnabled) {
      return raw;
    }
    final uid = _uidSource!.currentUid!;
    return raw.asyncMap(
      (messages) => _e2ee!.decryptMessages(
        uid: uid,
        matchId: matchId,
        messages: messages,
      ),
    );
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) async {
    final page = await _dataSource.loadOlder(
      matchId: matchId,
      before: before,
      limit: limit,
    );
    if (!_e2eeEnabled) {
      return page;
    }
    final uid = _uidSource!.currentUid!;
    final decrypted = await _e2ee!.decryptMessages(
      uid: uid,
      matchId: matchId,
      messages: page.messages,
    );
    return ChatPage(messages: decrypted, hasMore: page.hasMore);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) async {
    if (_e2eeEnabled) {
      final uid = _uidSource!.currentUid!;
      final ready = await _e2ee!.isSessionReady(
        uid: uid,
        matchId: matchId,
        peerUid: receiverId,
      );
      if (ready) {
        final payload = await _e2ee!.encryptText(
          uid: uid,
          matchId: matchId,
          peerUid: receiverId,
          plaintext: text,
        );
        final sent = await _dataSource.sendEncryptedMessage(
          matchId: matchId,
          receiverId: receiverId,
          type: MessageType.text,
          payload: payload,
        );
        return sent.copyWith(text: text, isEncrypted: true);
      }
    }
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
    final baseExtension = type == MessageType.voice
        ? _voiceExtension(media.contentType)
        : _imageExtension(media.contentType);

    var uploadBytes = media.bytes;
    E2eeMediaEnvelopeFields? envelopeFields;
    var encryptMedia = false;
    if (_e2eeEnabled) {
      final uid = _uidSource!.currentUid!;
      final ready = await _e2ee!.isSessionReady(
        uid: uid,
        matchId: matchId,
        peerUid: receiverId,
      );
      if (ready) {
        encryptMedia = true;
        final encrypted = await _e2ee!.encryptMedia(
          uid: uid,
          matchId: matchId,
          peerUid: receiverId,
          bytes: Uint8List.fromList(media.bytes),
        );
        uploadBytes = encrypted.encryptedBytes;
        envelopeFields = E2eeMediaEnvelopeFields(
          mediaNonceBase64: encrypted.mediaNonceBase64,
          mediaMacBase64: encrypted.mediaMacBase64,
          keyCiphertextBase64: encrypted.keyCiphertextBase64,
          keyNonceBase64: encrypted.keyNonceBase64,
          keyMacBase64: encrypted.keyMacBase64,
          encryptionVersion: encrypted.encryptionVersion,
          senderKeyVersion: encrypted.senderKeyVersion,
          originalContentType: media.contentType,
        );
      }
    }

    final extension = encryptMedia
        ? '$baseExtension.${E2eeConstants.encryptedFileExtension}'
        : baseExtension;
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
      bytes: uploadBytes,
      contentType: encryptMedia
          ? E2eeConstants.encryptedContentType
          : media.contentType,
      onProgress: onProgress,
    );
    switch (uploaded) {
      case Err(:final failure):
        throw failure;
      case Success(:final value):
        if (envelopeFields != null) {
          final uid = _uidSource!.currentUid!;
          final payload = await _e2ee!.encryptText(
            uid: uid,
            matchId: matchId,
            peerUid: receiverId,
            plaintext: '',
          );
          final sent = await _dataSource.sendEncryptedMessage(
            matchId: matchId,
            receiverId: receiverId,
            type: type,
            payload: payload,
            mediaEnvelope: envelopeFields,
            messageId: messageId,
            imageStoragePath: type == MessageType.image ? path : null,
            voiceStoragePath: type == MessageType.voice ? path : null,
            mediaUrl: value.toString(),
            durationMs: media.durationMs,
          );
          return sent.copyWith(
            localMediaBytes: media.bytes,
            isEncrypted: true,
          );
        }
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
