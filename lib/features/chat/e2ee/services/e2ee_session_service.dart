import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_crypto.dart';
import 'package:mevora/features/chat/e2ee/data/e2ee_secure_key_store.dart';
import 'package:mevora/features/chat/e2ee/data/firebase_e2ee_data_source.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';

/// Ensures local identity exists and publishes the public key to Firebase.
class E2eeIdentityService {
  E2eeIdentityService({
    E2eeSecureKeyStore? keyStore,
    FirebaseE2eeDataSource? remote,
  }) : _keyStore = keyStore ?? E2eeSecureKeyStore(),
       _remote = remote ?? FirebaseE2eeDataSource();

  final E2eeSecureKeyStore _keyStore;
  final FirebaseE2eeDataSource _remote;

  E2eeIdentity? _cachedIdentity;
  List<int>? _cachedPrivateKey;

  Future<E2eeIdentity> ensureIdentity(String uid) async {
    if (_cachedIdentity != null && _cachedPrivateKey != null) {
      return _cachedIdentity!;
    }
    var privateKey = await _keyStore.loadPrivateKey();
    if (privateKey == null) {
      final pair = await E2eeCrypto.generateKeyPair();
      privateKey = await pair.extractPrivateKeyBytes();
      await _keyStore.savePrivateKey(privateKey);
      final publicKey = await pair.extractPublicKey();
      final identity = E2eeIdentity(
        publicKeyBase64: await E2eeCrypto.publicKeyToBase64(publicKey),
        keyVersion: E2eeConstants.currentKeyVersion,
        algorithm: E2eeConstants.algorithm,
      );
      await _remote.publishIdentity(uid: uid, identity: identity);
      _cachedIdentity = identity;
      _cachedPrivateKey = privateKey;
      return identity;
    }

    final remote = await _remote.fetchIdentity(uid);
    if (remote != null) {
      _cachedIdentity = remote;
      _cachedPrivateKey = privateKey;
      return remote;
    }

    final publicKeyBase64 =
        await E2eeCrypto.publicKeyBase64FromPrivateKey(privateKey);
    final identity = E2eeIdentity(
      publicKeyBase64: publicKeyBase64,
      keyVersion: E2eeConstants.currentKeyVersion,
      algorithm: E2eeConstants.algorithm,
    );
    await _remote.publishIdentity(uid: uid, identity: identity);
    _cachedIdentity = identity;
    _cachedPrivateKey = privateKey;
    return identity;
  }

  Future<List<int>> privateKeyBytes() async {
    final key = _cachedPrivateKey ?? await _keyStore.loadPrivateKey();
    if (key == null) {
      throw StateError('E2EE identity is not initialized');
    }
    return key;
  }

  Future<int> keyVersion() async {
    final identity = _cachedIdentity;
    return identity?.keyVersion ?? E2eeConstants.currentKeyVersion;
  }

  Future<void> clearLocalIdentity() async {
    _cachedIdentity = null;
    _cachedPrivateKey = null;
    await _keyStore.deleteAllKeys();
  }
}

class E2eeSession {
  const E2eeSession({
    required this.matchId,
    required this.peerUid,
    required this.sessionKey,
    required this.localKeyVersion,
    required this.peerIdentity,
    required this.isReady,
  });

  final String matchId;
  final String peerUid;
  final SecretKey? sessionKey;
  final int localKeyVersion;
  final E2eeIdentity? peerIdentity;
  final bool isReady;
}

/// Derives per-match symmetric keys via X25519 + HKDF.
class E2eeSessionService {
  E2eeSessionService({
    E2eeIdentityService? identityService,
    FirebaseE2eeDataSource? remote,
  }) : _identity = identityService ?? E2eeIdentityService(),
       _remote = remote ?? FirebaseE2eeDataSource();

  final E2eeIdentityService _identity;
  final FirebaseE2eeDataSource _remote;
  final Map<String, E2eeSession> _cache = {};

  Future<E2eeSession> ensureSession({
    required String uid,
    required String matchId,
    required String peerUid,
  }) async {
    final cacheKey = '$matchId:$peerUid';
    final cached = _cache[cacheKey];
    if (cached != null && cached.isReady) {
      return cached;
    }

    await _identity.ensureIdentity(uid);
    final peer = await _remote.fetchIdentity(peerUid);
    if (peer == null) {
      final pending = E2eeSession(
        matchId: matchId,
        peerUid: peerUid,
        sessionKey: null,
        localKeyVersion: await _identity.keyVersion(),
        peerIdentity: null,
        isReady: false,
      );
      _cache[cacheKey] = pending;
      return pending;
    }

    final privateKey = await _identity.privateKeyBytes();
    final sessionKey = await E2eeCrypto.deriveSessionKey(
      privateKeyBytes: privateKey,
      peerPublicKeyBase64: peer.publicKeyBase64,
      matchId: matchId,
    );
    final session = E2eeSession(
      matchId: matchId,
      peerUid: peerUid,
      sessionKey: sessionKey,
      localKeyVersion: await _identity.keyVersion(),
      peerIdentity: peer,
      isReady: true,
    );
    _cache[cacheKey] = session;
    return session;
  }

  void invalidateMatch(String matchId) {
    _cache.removeWhere((key, _) => key.startsWith('$matchId:'));
  }

  void clear() => _cache.clear();
}
