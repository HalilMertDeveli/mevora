import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/storage/storage_provider.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_crypto.dart';
import 'package:mevora/features/chat/e2ee/services/decrypted_media_cache.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_chat_service.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_session_service.dart';

const _matchId = 'match-1';
const _path = 'users/peer/chat/match-1/blob-1';

class _Sessions implements E2eeSessionService {
  _Sessions(this.key);

  final SecretKey key;

  @override
  Future<E2eeSession> ensureSession({
    required String uid,
    required String matchId,
    required String peerUid,
  }) async => E2eeSession(
    matchId: matchId,
    peerUid: peerUid,
    sessionKey: key,
    localKeyVersion: 1,
    peerIdentity: null,
    isReady: true,
  );

  @override
  void invalidateMatch(String matchId) {}

  @override
  void clear() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements StorageProvider {
  _Storage(this.blobs);

  final Map<String, Uint8List> blobs;
  int downloads = 0;
  bool fail = false;

  @override
  Future<Result<List<int>>> downloadBytes(String path) async {
    downloads++;
    if (fail || !blobs.containsKey(path)) {
      return const Err(NetworkFailure('unavailable'));
    }
    return Success(blobs[path]!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SecretKey key;
  late _Storage storage;
  late ChatMessage message;
  final clear = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));

  setUp(() async {
    key = SecretKey(List<int>.generate(32, (i) => i));
    final encrypted = await E2eeCrypto.encryptMediaBytes(
      sessionKey: key,
      bytes: clear,
      senderKeyVersion: 1,
    );
    storage = _Storage({_path: encrypted.encryptedBytes});
    message = ChatMessage(
      id: 'msg-1',
      senderId: 'peer',
      receiverId: 'me',
      text: '',
      type: MessageType.image,
      createdAt: DateTime(2026, 9, 30),
      status: MessageStatus.sent,
      isEncrypted: true,
      imageStoragePath: _path,
      mediaEnvelope: E2eeMediaEnvelopeFields(
        mediaNonceBase64: encrypted.mediaNonceBase64,
        mediaMacBase64: encrypted.mediaMacBase64,
        keyCiphertextBase64: encrypted.keyCiphertextBase64,
        keyNonceBase64: encrypted.keyNonceBase64,
        keyMacBase64: encrypted.keyMacBase64,
        encryptionVersion: encrypted.encryptionVersion,
        senderKeyVersion: encrypted.senderKeyVersion,
      ),
    );
  });

  E2eeChatService service() =>
      E2eeChatService(sessions: _Sessions(key), storage: storage);

  test(
    'repeated message-window snapshots download and decrypt media once',
    () async {
      final e2ee = service();
      for (var snapshot = 0; snapshot < 5; snapshot++) {
        final out = await e2ee.decryptMessages(
          uid: 'me',
          matchId: _matchId,
          messages: [message],
        );
        expect(out.single.decryptFailed, isFalse);
        expect(out.single.localMediaBytes, clear);
      }
      expect(storage.downloads, 1);
    },
  );

  test('concurrent snapshots share one download', () async {
    final e2ee = service();
    await Future.wait([
      e2ee.decryptMessages(uid: 'me', matchId: _matchId, messages: [message]),
      e2ee.decryptMessages(uid: 'me', matchId: _matchId, messages: [message]),
    ]);
    expect(storage.downloads, 1);
  });

  test(
    'a failed download is retried on the next snapshot, not cached',
    () async {
      final e2ee = service();
      storage.fail = true;
      final first = await e2ee.decryptMessage(
        uid: 'me',
        matchId: _matchId,
        message: message,
      );
      expect(first.decryptFailed, isTrue);
      storage.fail = false;
      final second = await e2ee.decryptMessage(
        uid: 'me',
        matchId: _matchId,
        message: message,
      );
      expect(second.decryptFailed, isFalse);
      expect(storage.downloads, 2);
    },
  );

  test(
    'another account signing in never sees the previous plaintext',
    () async {
      final e2ee = service();
      await e2ee.decryptMessage(uid: 'me', matchId: _matchId, message: message);
      await e2ee.decryptMessage(
        uid: 'someone-else',
        matchId: _matchId,
        message: message,
      );
      expect(storage.downloads, 2);
    },
  );

  test('invalidating the match drops its media', () async {
    final e2ee = service();
    await e2ee.decryptMessage(uid: 'me', matchId: _matchId, message: message);
    e2ee.invalidateMatch(_matchId);
    await e2ee.decryptMessage(uid: 'me', matchId: _matchId, message: message);
    expect(storage.downloads, 2);
  });

  group('DecryptedMediaCache', () {
    test('evicts least recently used past its byte budget', () {
      final cache = DecryptedMediaCache(maxBytes: 250);
      cache
        ..put('m/a/p', Uint8List(100))
        ..put('m/b/p', Uint8List(100));
      cache.get('m/a/p'); // a is now most recent
      cache.put('m/c/p', Uint8List(100));
      expect(cache.get('m/b/p'), isNull);
      expect(cache.get('m/a/p'), isNotNull);
      expect(cache.bytes, 200);
    });

    test('never holds an entry larger than the whole budget', () {
      final cache = DecryptedMediaCache(maxBytes: 50)
        ..put('m/a/p', Uint8List(60));
      expect(cache.length, 0);
    });
  });
}
