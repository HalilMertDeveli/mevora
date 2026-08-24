import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_crypto.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';

void main() {
  test('text encrypt/decrypt roundtrip with derived session key', () async {
    final alicePair = await E2eeCrypto.generateKeyPair();
    final bobPair = await E2eeCrypto.generateKeyPair();
    final alicePrivate = await alicePair.extractPrivateKeyBytes();
    final bobPrivate = await bobPair.extractPrivateKeyBytes();
    final alicePublic = await E2eeCrypto.publicKeyToBase64(
      await alicePair.extractPublicKey(),
    );
    final bobPublic = await E2eeCrypto.publicKeyToBase64(
      await bobPair.extractPublicKey(),
    );

    const matchId = 'user_a_user_b';
    final aliceSession = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: alicePrivate,
      peerPublicKeyBase64: bobPublic,
      matchId: matchId,
    );
    final bobSession = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: bobPrivate,
      peerPublicKeyBase64: alicePublic,
      matchId: matchId,
    );

    const plaintext = 'Merhaba';
    final encrypted = await E2eeCrypto.encryptText(
      sessionKey: aliceSession,
      plaintext: plaintext,
      senderKeyVersion: E2eeConstants.currentKeyVersion,
    );

    expect(encrypted.ciphertextBase64, isNot(contains('Merhaba')));
    expect(base64Decode(encrypted.ciphertextBase64), isNot(contains('Merhaba')));

    final decrypted = await E2eeCrypto.decryptText(
      sessionKey: bobSession,
      payload: encrypted,
    );
    expect(decrypted, plaintext);
  });

  test('wrong session key fails authentication', () async {
    final alicePair = await E2eeCrypto.generateKeyPair();
    final evePair = await E2eeCrypto.generateKeyPair();
    final alicePrivate = await alicePair.extractPrivateKeyBytes();
    final evePublic = await E2eeCrypto.publicKeyToBase64(
      await evePair.extractPublicKey(),
    );

    final aliceSession = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: alicePrivate,
      peerPublicKeyBase64: evePublic,
      matchId: 'match_1',
    );
    final encrypted = await E2eeCrypto.encryptText(
      sessionKey: aliceSession,
      plaintext: 'secret',
      senderKeyVersion: 1,
    );

  final bobPair = await E2eeCrypto.generateKeyPair();
    final bobPrivate = await bobPair.extractPrivateKeyBytes();
    final alicePublic = await E2eeCrypto.publicKeyToBase64(
      await alicePair.extractPublicKey(),
    );
    final bobSession = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: bobPrivate,
      peerPublicKeyBase64: alicePublic,
      matchId: 'match_1',
    );

    expect(
      () => E2eeCrypto.decryptText(sessionKey: bobSession, payload: encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('media encrypt/decrypt roundtrip', () async {
    final alicePair = await E2eeCrypto.generateKeyPair();
    final bobPair = await E2eeCrypto.generateKeyPair();
    final alicePrivate = await alicePair.extractPrivateKeyBytes();
    final bobPrivate = await bobPair.extractPrivateKeyBytes();
    final alicePublic = await E2eeCrypto.publicKeyToBase64(
      await alicePair.extractPublicKey(),
    );
    final bobPublic = await E2eeCrypto.publicKeyToBase64(
      await bobPair.extractPublicKey(),
    );

    const matchId = 'audio_match';
    final aliceSession = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: alicePrivate,
      peerPublicKeyBase64: bobPublic,
      matchId: matchId,
    );
    final bobSession = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: bobPrivate,
      peerPublicKeyBase64: alicePublic,
      matchId: matchId,
    );

    final audioBytes = Uint8List.fromList(List<int>.generate(256, (i) => i % 251));
    final encrypted = await E2eeCrypto.encryptMediaBytes(
      sessionKey: aliceSession,
      bytes: audioBytes,
      senderKeyVersion: 1,
    );

    expect(encrypted.encryptedBytes, isNot(equals(audioBytes)));

    final decrypted = await E2eeCrypto.decryptMediaBytes(
      sessionKey: bobSession,
      encryptedBytes: encrypted.encryptedBytes,
      mediaNonceBase64: encrypted.mediaNonceBase64,
      mediaMacBase64: encrypted.mediaMacBase64,
      keyCiphertextBase64: encrypted.keyCiphertextBase64,
      keyNonceBase64: encrypted.keyNonceBase64,
      keyMacBase64: encrypted.keyMacBase64,
    );
    expect(decrypted, audioBytes);
  });

  test('public key can be derived from stored private key seed', () async {
    final pair = await E2eeCrypto.generateKeyPair();
    final privateKey = await pair.extractPrivateKeyBytes();
    final published = await E2eeCrypto.publicKeyBase64FromPrivateKey(privateKey);
    final expected = await E2eeCrypto.publicKeyToBase64(
      await pair.extractPublicKey(),
    );
    expect(published, expected);
  });
}
