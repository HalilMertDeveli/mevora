import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';

/// Stores E2EE private key material only on-device (Android Keystore / iOS Keychain).
class E2eeSecureKeyStore {
  E2eeSecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _privateKeyKey(int version) => 'mevora_e2ee_private_v$version';

  Future<List<int>?> loadPrivateKey({int version = E2eeConstants.currentKeyVersion}) async {
    final raw = await _storage.read(key: _privateKeyKey(version));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return base64Decode(raw);
  }

  Future<void> savePrivateKey(
    List<int> privateKeyBytes, {
    int version = E2eeConstants.currentKeyVersion,
  }) async {
    await _storage.write(
      key: _privateKeyKey(version),
      value: base64Encode(privateKeyBytes),
    );
  }

  Future<void> deleteAllKeys() async {
    await _storage.delete(key: _privateKeyKey(E2eeConstants.currentKeyVersion));
  }
}
