import 'dart:typed_data';

import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/storage/storage_provider.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_crypto.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_session_service.dart';

/// Encrypts/decrypts chat payloads on-device. Firebase only sees ciphertext.
class E2eeChatService {
  E2eeChatService({
    E2eeSessionService? sessions,
    StorageProvider? storage,
  }) : _sessions = sessions ?? E2eeSessionService(),
       _storage = storage;

  final E2eeSessionService _sessions;
  final StorageProvider? _storage;

  Future<bool> isSessionReady({
    required String uid,
    required String matchId,
    required String peerUid,
  }) async {
    final session = await _sessions.ensureSession(
      uid: uid,
      matchId: matchId,
      peerUid: peerUid,
    );
    return session.isReady;
  }

  Future<E2eeEncryptedPayload> encryptText({
    required String uid,
    required String matchId,
    required String peerUid,
    required String plaintext,
  }) async {
    final session = await _sessions.ensureSession(
      uid: uid,
      matchId: matchId,
      peerUid: peerUid,
    );
    if (!session.isReady || session.sessionKey == null) {
      throw StateError('E2EE session is not ready');
    }
    return E2eeCrypto.encryptText(
      sessionKey: session.sessionKey!,
      plaintext: plaintext,
      senderKeyVersion: session.localKeyVersion,
    );
  }

  Future<E2eeMediaEncryptionResult> encryptMedia({
    required String uid,
    required String matchId,
    required String peerUid,
    required Uint8List bytes,
  }) async {
    final session = await _sessions.ensureSession(
      uid: uid,
      matchId: matchId,
      peerUid: peerUid,
    );
    if (!session.isReady || session.sessionKey == null) {
      throw StateError('E2EE session is not ready');
    }
    return E2eeCrypto.encryptMediaBytes(
      sessionKey: session.sessionKey!,
      bytes: bytes,
      senderKeyVersion: session.localKeyVersion,
    );
  }

  Future<ChatMessage> decryptMessage({
    required String uid,
    required String matchId,
    required ChatMessage message,
  }) async {
    if (!message.isEncrypted) {
      return message;
    }
    final peerUid =
        message.senderId == uid ? message.receiverId : message.senderId;
    final session = await _sessions.ensureSession(
      uid: uid,
      matchId: matchId,
      peerUid: peerUid,
    );
    if (!session.isReady || session.sessionKey == null) {
      return message.copyWith(
        decryptFailed: true,
        text: '',
      );
    }
    try {
      var decrypted = message;
      if (message.type == MessageType.text && message.encryptedPayload != null) {
        final clear = await E2eeCrypto.decryptText(
          sessionKey: session.sessionKey!,
          payload: message.encryptedPayload!,
        );
        decrypted = decrypted.copyWith(text: clear, decryptFailed: false);
      }
      if (message.mediaEnvelope != null && message.localMediaBytes == null) {
        final path = message.storagePath;
        final storage = _storage;
        if (storage == null || path == null) {
          return decrypted.copyWith(decryptFailed: true);
        }
        final downloaded = await storage.downloadBytes(path);
        switch (downloaded) {
          case Err():
            return decrypted.copyWith(decryptFailed: true);
          case Success(:final value):
            final envelope = message.mediaEnvelope!;
            final clear = await E2eeCrypto.decryptMediaBytes(
              sessionKey: session.sessionKey!,
              encryptedBytes: Uint8List.fromList(value),
              mediaNonceBase64: envelope.mediaNonceBase64,
              mediaMacBase64: envelope.mediaMacBase64,
              keyCiphertextBase64: envelope.keyCiphertextBase64,
              keyNonceBase64: envelope.keyNonceBase64,
              keyMacBase64: envelope.keyMacBase64,
            );
            decrypted = decrypted.copyWith(
              localMediaBytes: clear,
              decryptFailed: false,
            );
        }
      }
      return decrypted;
    } on Object {
      return message.copyWith(decryptFailed: true, text: '');
    }
  }

  Future<List<ChatMessage>> decryptMessages({
    required String uid,
    required String matchId,
    required List<ChatMessage> messages,
  }) async {
    final decrypted = <ChatMessage>[];
    for (final message in messages) {
      decrypted.add(
        await decryptMessage(uid: uid, matchId: matchId, message: message),
      );
    }
    return decrypted;
  }

  void invalidateMatch(String matchId) => _sessions.invalidateMatch(matchId);

  void clear() => _sessions.clear();
}

class E2eeMediaEnvelopeFields {
  const E2eeMediaEnvelopeFields({
    required this.mediaNonceBase64,
    required this.mediaMacBase64,
    required this.keyCiphertextBase64,
    required this.keyNonceBase64,
    required this.keyMacBase64,
    required this.encryptionVersion,
    required this.senderKeyVersion,
    this.originalContentType,
  });

  final String mediaNonceBase64;
  final String mediaMacBase64;
  final String keyCiphertextBase64;
  final String keyNonceBase64;
  final String keyMacBase64;
  final int encryptionVersion;
  final int senderKeyVersion;
  final String? originalContentType;

  Map<String, dynamic> toFirestore() {
    return {
      'mediaNonce': mediaNonceBase64,
      'mediaMac': mediaMacBase64,
      'mediaKeyCiphertext': keyCiphertextBase64,
      'mediaKeyNonce': keyNonceBase64,
      'mediaKeyMac': keyMacBase64,
      'encryptionVersion': encryptionVersion,
      'senderKeyVersion': senderKeyVersion,
      if (originalContentType != null) 'originalContentType': originalContentType,
      'encrypted': true,
    };
  }

  static E2eeMediaEnvelopeFields? fromFirestore(Map<String, dynamic> data) {
    if (data['encrypted'] != true) {
      return null;
    }
    final mediaNonce = data['mediaNonce'] as String?;
    final mediaMac = data['mediaMac'] as String?;
    final keyCipher = data['mediaKeyCiphertext'] as String?;
    final keyNonce = data['mediaKeyNonce'] as String?;
    final keyMac = data['mediaKeyMac'] as String?;
    if (mediaNonce == null ||
        mediaMac == null ||
        keyCipher == null ||
        keyNonce == null ||
        keyMac == null) {
      return null;
    }
    return E2eeMediaEnvelopeFields(
      mediaNonceBase64: mediaNonce,
      mediaMacBase64: mediaMac,
      keyCiphertextBase64: keyCipher,
      keyNonceBase64: keyNonce,
      keyMacBase64: keyMac,
      encryptionVersion: (data['encryptionVersion'] as num?)?.toInt() ?? 1,
      senderKeyVersion: (data['senderKeyVersion'] as num?)?.toInt() ?? 1,
      originalContentType: data['originalContentType'] as String?,
    );
  }
}
