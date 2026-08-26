import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';

class E2eeMediaEncryptionResult {
  const E2eeMediaEncryptionResult({
    required this.encryptedBytes,
    required this.mediaNonceBase64,
    required this.mediaMacBase64,
    required this.keyCiphertextBase64,
    required this.keyNonceBase64,
    required this.keyMacBase64,
    required this.encryptionVersion,
    required this.senderKeyVersion,
  });

  final Uint8List encryptedBytes;
  final String mediaNonceBase64;
  final String mediaMacBase64;
  final String keyCiphertextBase64;
  final String keyNonceBase64;
  final String keyMacBase64;
  final int encryptionVersion;
  final int senderKeyVersion;
}

/// Low-level E2EE primitives. Uses [cryptography] — no custom crypto.
abstract final class E2eeCrypto {
  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SimpleKeyPair> generateKeyPair() {
    return _x25519.newKeyPair();
  }

  static Future<String> publicKeyToBase64(SimplePublicKey publicKey) async {
    return base64Encode(publicKey.bytes);
  }

  static Future<String> publicKeyBase64FromPrivateKey(
    List<int> privateKeyBytes,
  ) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
    final publicKey = await keyPair.extractPublicKey();
    return publicKeyToBase64(publicKey);
  }

  static SimplePublicKey publicKeyFromBase64(String value) {
    return SimplePublicKey(
      base64Decode(value),
      type: KeyPairType.x25519,
    );
  }

  static Future<SecretKey> deriveSessionKey({
    required List<int> privateKeyBytes,
    required String peerPublicKeyBase64,
    required String matchId,
  }) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: publicKeyFromBase64(peerPublicKeyBase64),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(matchId),
      info: utf8.encode(E2eeConstants.hkdfInfo),
    );
  }

  static Future<E2eeEncryptedPayload> encryptText({
    required SecretKey sessionKey,
    required String plaintext,
    required int senderKeyVersion,
  }) async {
    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: sessionKey,
    );
    return E2eeEncryptedPayload(
      ciphertextBase64: base64Encode(box.cipherText),
      nonceBase64: base64Encode(box.nonce),
      macBase64: base64Encode(box.mac.bytes),
      encryptionVersion: E2eeConstants.currentKeyVersion,
      senderKeyVersion: senderKeyVersion,
    );
  }

  static Future<String> decryptText({
    required SecretKey sessionKey,
    required E2eeEncryptedPayload payload,
  }) async {
    final box = SecretBox(
      base64Decode(payload.ciphertextBase64),
      nonce: base64Decode(payload.nonceBase64),
      mac: Mac(base64Decode(payload.macBase64)),
    );
    final clear = await _aesGcm.decrypt(box, secretKey: sessionKey);
    return utf8.decode(clear);
  }

  static Future<E2eeMediaEncryptionResult> encryptMediaBytes({
    required SecretKey sessionKey,
    required Uint8List bytes,
    required int senderKeyVersion,
  }) async {
    final contentKey = await _aesGcm.newSecretKey();
    final contentKeyBytes = await contentKey.extractBytes();
    final encrypted = await _aesGcm.encrypt(bytes, secretKey: contentKey);
    final wrapped = await _aesGcm.encrypt(
      contentKeyBytes,
      secretKey: sessionKey,
    );
    return E2eeMediaEncryptionResult(
      encryptedBytes: Uint8List.fromList(encrypted.cipherText),
      mediaNonceBase64: base64Encode(encrypted.nonce),
      mediaMacBase64: base64Encode(encrypted.mac.bytes),
      keyCiphertextBase64: base64Encode(wrapped.cipherText),
      keyNonceBase64: base64Encode(wrapped.nonce),
      keyMacBase64: base64Encode(wrapped.mac.bytes),
      encryptionVersion: E2eeConstants.currentKeyVersion,
      senderKeyVersion: senderKeyVersion,
    );
  }

  static Future<Uint8List> decryptMediaBytes({
    required SecretKey sessionKey,
    required Uint8List encryptedBytes,
    required String mediaNonceBase64,
    required String mediaMacBase64,
    required String keyCiphertextBase64,
    required String keyNonceBase64,
    required String keyMacBase64,
  }) async {
    final wrapped = SecretBox(
      base64Decode(keyCiphertextBase64),
      nonce: base64Decode(keyNonceBase64),
      mac: Mac(base64Decode(keyMacBase64)),
    );
    final contentKeyBytes = await _aesGcm.decrypt(wrapped, secretKey: sessionKey);
    final contentKey = SecretKey(contentKeyBytes);
    final mediaBox = SecretBox(
      encryptedBytes,
      nonce: base64Decode(mediaNonceBase64),
      mac: Mac(base64Decode(mediaMacBase64)),
    );
    final clear = await _aesGcm.decrypt(mediaBox, secretKey: contentKey);
    return Uint8List.fromList(clear);
  }
}
