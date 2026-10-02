import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';

/// Stores E2EE private key material only on-device (Android Keystore / iOS Keychain).
///
/// Every key is stored under the member it belongs to. A device that is used
/// by more than one account keeps each account's key apart, and signing out
/// does not have to destroy a key to keep the next account away from it — so
/// signing back in on the same device can still read the old conversations.
class E2eeSecureKeyStore {
  E2eeSecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
          );

  final FlutterSecureStorage _storage;

  String _privateKeyKey(String uid, int version) =>
      'mevora_e2ee_private_v${version}_$uid';

  /// Where the key lived before keys were stored per member: one slot for
  /// whoever was signed in.
  String _legacyPrivateKeyKey(int version) => 'mevora_e2ee_private_v$version';

  Future<List<int>?> loadPrivateKey(
    String uid, {
    int version = E2eeConstants.currentKeyVersion,
  }) {
    return _read(_privateKeyKey(uid, version));
  }

  Future<void> savePrivateKey(
    String uid,
    List<int> privateKeyBytes, {
    int version = E2eeConstants.currentKeyVersion,
  }) async {
    await _storage.write(
      key: _privateKeyKey(uid, version),
      value: base64Encode(privateKeyBytes),
    );
  }

  /// Removes one member's key. Only for an account that no longer exists.
  Future<void> deletePrivateKey(
    String uid, {
    int version = E2eeConstants.currentKeyVersion,
  }) async {
    await _storage.delete(key: _privateKeyKey(uid, version));
  }

  /// The key an older build stored without an owner, if there is one.
  Future<List<int>?> loadLegacyPrivateKey({
    int version = E2eeConstants.currentKeyVersion,
  }) {
    return _read(_legacyPrivateKeyKey(version));
  }

  Future<void> deleteLegacyPrivateKey({
    int version = E2eeConstants.currentKeyVersion,
  }) async {
    await _storage.delete(key: _legacyPrivateKeyKey(version));
  }

  Future<List<int>?> _read(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return base64Decode(raw);
  }
}
