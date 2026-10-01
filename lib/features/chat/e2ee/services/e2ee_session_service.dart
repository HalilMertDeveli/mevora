import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_constants.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_crypto.dart';
import 'package:mevora/features/chat/e2ee/data/e2ee_secure_key_store.dart';
import 'package:mevora/features/chat/e2ee/data/firebase_e2ee_data_source.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';

/// Ensures local identity exists and publishes the public key to Firebase.
///
/// The private key is kept per member (see [E2eeSecureKeyStore]) and survives
/// a sign-out: deleting it made every earlier message undecryptable for both
/// sides the next time the member signed in, because a new key pair replaced
/// the published one.
class E2eeIdentityService {
  E2eeIdentityService({
    E2eeSecureKeyStore? keyStore,
    FirebaseE2eeDataSource? remote,
  }) : _keyStore = keyStore ?? E2eeSecureKeyStore(),
       _remote = remote ?? FirebaseE2eeDataSource();

  final E2eeSecureKeyStore _keyStore;
  final FirebaseE2eeDataSource _remote;

  /// Whose identity the two fields below hold. This service outlives a
  /// session, so an identity is only ever served to the member it belongs to.
  String? _cachedUid;
  E2eeIdentity? _cachedIdentity;
  List<int>? _cachedPrivateKey;

  Future<E2eeIdentity> ensureIdentity(String uid) async {
    if (_cachedUid == uid &&
        _cachedIdentity != null &&
        _cachedPrivateKey != null) {
      return _cachedIdentity!;
    }
    var privateKey = await _keyStore.loadPrivateKey(uid);
    privateKey ??= await _adoptLegacyKey(uid);
    if (privateKey == null) {
      final pair = await E2eeCrypto.generateKeyPair();
      privateKey = await pair.extractPrivateKeyBytes();
      await _keyStore.savePrivateKey(uid, privateKey);
      final publicKey = await pair.extractPublicKey();
      final identity = E2eeIdentity(
        publicKeyBase64: await E2eeCrypto.publicKeyToBase64(publicKey),
        keyVersion: E2eeConstants.currentKeyVersion,
        algorithm: E2eeConstants.algorithm,
      );
      await _publish(uid, identity);
      return _remember(uid, identity, privateKey);
    }

    final publicKeyBase64 = await E2eeCrypto.publicKeyBase64FromPrivateKey(
      privateKey,
    );
    final remote = await _remote.fetchIdentity(uid);
    if (remote != null && remote.publicKeyBase64 == publicKeyBase64) {
      return _remember(uid, remote, privateKey);
    }

    // Nothing published, or another install published a different key. This
    // device can only ever decrypt with the key it holds, so that is the one
    // peers have to encrypt to.
    final identity = E2eeIdentity(
      publicKeyBase64: publicKeyBase64,
      keyVersion: E2eeConstants.currentKeyVersion,
      algorithm: E2eeConstants.algorithm,
    );
    await _publish(uid, identity);
    return _remember(uid, identity, privateKey);
  }

  Future<List<int>> privateKeyBytes(String uid) async {
    final key = _cachedUid == uid
        ? _cachedPrivateKey
        : await _keyStore.loadPrivateKey(uid);
    if (key == null) {
      throw StateError('E2EE identity is not initialized');
    }
    return key;
  }

  Future<int> keyVersion() async {
    final identity = _cachedIdentity;
    return identity?.keyVersion ?? E2eeConstants.currentKeyVersion;
  }

  /// Forgets the in-memory identity when the signed-in member changes. The
  /// stored key stays: it is the only thing that can read that member's
  /// conversations when they sign in on this device again.
  void forgetCachedIdentity() {
    _cachedUid = null;
    _cachedIdentity = null;
    _cachedPrivateKey = null;
  }

  /// Removes a member's key from this device. For a deleted account only.
  Future<void> deleteLocalIdentity(String uid) async {
    if (_cachedUid == uid) {
      forgetCachedIdentity();
    }
    await _keyStore.deletePrivateKey(uid);
  }

  /// Builds before per-member storage kept one key for whoever was signed in.
  /// It becomes [uid]'s only when it is provably theirs: its public half is
  /// the identity they have published. Otherwise it belonged to a session
  /// that is gone, and it is dropped.
  Future<List<int>?> _adoptLegacyKey(String uid) async {
    final legacy = await _keyStore.loadLegacyPrivateKey();
    if (legacy == null) {
      return null;
    }
    final remote = await _remote.fetchIdentity(uid);
    final legacyPublic = await E2eeCrypto.publicKeyBase64FromPrivateKey(legacy);
    await _keyStore.deleteLegacyPrivateKey();
    if (remote == null || remote.publicKeyBase64 != legacyPublic) {
      return null;
    }
    await _keyStore.savePrivateKey(uid, legacy);
    return legacy;
  }

  Future<void> _publish(String uid, E2eeIdentity identity) async {
    try {
      await _remote.publishIdentity(uid: uid, identity: identity);
    } on Object {
      // Public-key publish is best-effort; local identity still works for E2EE.
    }
  }

  E2eeIdentity _remember(
    String uid,
    E2eeIdentity identity,
    List<int> privateKey,
  ) {
    _cachedUid = uid;
    _cachedIdentity = identity;
    _cachedPrivateKey = privateKey;
    return identity;
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
    final cacheKey = '$uid:$matchId:$peerUid';
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

    final privateKey = await _identity.privateKeyBytes(uid);
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
    _cache.removeWhere((key, _) => key.contains(':$matchId:'));
  }

  void clear() => _cache.clear();
}
