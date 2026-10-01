import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/chat/e2ee/crypto/e2ee_crypto.dart';
import 'package:mevora/features/chat/e2ee/data/e2ee_secure_key_store.dart';
import 'package:mevora/features/chat/e2ee/data/firebase_e2ee_data_source.dart';
import 'package:mevora/features/chat/e2ee/models/e2ee_identity.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_session_service.dart';

/// `users/{uid}/crypto/identity`, in memory.
class _FakeRemote implements FirebaseE2eeDataSource {
  final published = <String, E2eeIdentity>{};
  var publishCount = 0;

  @override
  Future<E2eeIdentity?> fetchIdentity(String uid) async => published[uid];

  @override
  Future<void> publishIdentity({
    required String uid,
    required E2eeIdentity identity,
  }) async {
    publishCount += 1;
    published[uid] = identity;
  }
}

const _legacySlot = 'mevora_e2ee_private_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRemote remote;

  /// A new service over the same device storage stands in for an app restart.
  E2eeIdentityService service() =>
      E2eeIdentityService(keyStore: E2eeSecureKeyStore(), remote: remote);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    remote = _FakeRemote();
  });

  test('signing out and back in keeps the same key', () async {
    final first = service();
    final before = await first.ensureIdentity('user-a');
    final keyBefore = await first.privateKeyBytes('user-a');

    // What E2eeBootstrapController does when the signed-in member changes.
    first.forgetCachedIdentity();

    final after = await first.ensureIdentity('user-a');
    expect(after.publicKeyBase64, before.publicKeyBase64);
    expect(await first.privateKeyBytes('user-a'), keyBefore);
    expect(remote.published['user-a']!.publicKeyBase64, before.publicKeyBase64);
    expect(remote.publishCount, 1);
  });

  test('an app restart keeps the same key', () async {
    final before = await service().ensureIdentity('user-a');
    final after = await service().ensureIdentity('user-a');
    expect(after.publicKeyBase64, before.publicKeyBase64);
    expect(remote.publishCount, 1);
  });

  test('two members on one device never share a key', () async {
    final identities = service();
    final a = await identities.ensureIdentity('user-a');
    final keyA = await identities.privateKeyBytes('user-a');

    // Same process, the next member signs in without a restart.
    identities.forgetCachedIdentity();
    final b = await identities.ensureIdentity('user-b');
    final keyB = await identities.privateKeyBytes('user-b');

    expect(b.publicKeyBase64, isNot(a.publicKeyBase64));
    expect(keyB, isNot(keyA));
    expect(remote.published['user-a']!.publicKeyBase64, a.publicKeyBase64);
    expect(remote.published['user-b']!.publicKeyBase64, b.publicKeyBase64);

    identities.forgetCachedIdentity();
    final again = await identities.ensureIdentity('user-a');
    expect(again.publicKeyBase64, a.publicKeyBase64);
    expect(await identities.privateKeyBytes('user-a'), keyA);
  });

  test('a cached identity is never served to another member', () async {
    final identities = service();
    final a = await identities.ensureIdentity('user-a');
    // No forgetCachedIdentity() in between: the cache alone must not leak.
    final b = await identities.ensureIdentity('user-b');
    expect(b.publicKeyBase64, isNot(a.publicKeyBase64));
    expect(
      await identities.privateKeyBytes('user-b'),
      isNot(await identities.privateKeyBytes('user-a')),
    );
  });

  test(
    'a key stored by an older build is adopted when it is the member\'s own',
    () async {
      final pair = await E2eeCrypto.generateKeyPair();
      final legacyKey = await pair.extractPrivateKeyBytes();
      final legacyPublic = await E2eeCrypto.publicKeyBase64FromPrivateKey(
        legacyKey,
      );
      FlutterSecureStorage.setMockInitialValues({
        _legacySlot: base64Encode(legacyKey),
      });
      remote.published['user-a'] = E2eeIdentity(
        publicKeyBase64: legacyPublic,
        keyVersion: 1,
        algorithm: 'x25519-aes256gcm-v1',
      );

      final identities = service();
      final identity = await identities.ensureIdentity('user-a');

      expect(identity.publicKeyBase64, legacyPublic);
      expect(await identities.privateKeyBytes('user-a'), legacyKey);
      expect(remote.publishCount, 0);
      expect(await E2eeSecureKeyStore().loadLegacyPrivateKey(), isNull);
      expect(await E2eeSecureKeyStore().loadPrivateKey('user-a'), legacyKey);
    },
  );

  test('a key left by someone else\'s session is not adopted', () async {
    final stranger = await E2eeCrypto.generateKeyPair();
    final strangerKey = await stranger.extractPrivateKeyBytes();
    FlutterSecureStorage.setMockInitialValues({
      _legacySlot: base64Encode(strangerKey),
    });

    final identities = service();
    final identity = await identities.ensureIdentity('user-a');

    expect(await identities.privateKeyBytes('user-a'), isNot(strangerKey));
    expect(
      identity.publicKeyBase64,
      isNot(await E2eeCrypto.publicKeyBase64FromPrivateKey(strangerKey)),
    );
    expect(await E2eeSecureKeyStore().loadLegacyPrivateKey(), isNull);
  });

  test(
    'a key published by another install is replaced by this device\'s own',
    () async {
      final identities = service();
      final mine = await identities.ensureIdentity('user-a');

      final other = await E2eeCrypto.generateKeyPair();
      remote.published['user-a'] = E2eeIdentity(
        publicKeyBase64: await E2eeCrypto.publicKeyToBase64(
          await other.extractPublicKey(),
        ),
        keyVersion: 1,
        algorithm: 'x25519-aes256gcm-v1',
      );

      final afterRestart = await service().ensureIdentity('user-a');
      expect(afterRestart.publicKeyBase64, mine.publicKeyBase64);
      expect(remote.published['user-a']!.publicKeyBase64, mine.publicKeyBase64);
    },
  );

  test('deleting the account removes the key from the device', () async {
    final identities = service();
    final before = await identities.ensureIdentity('user-a');

    await identities.deleteLocalIdentity('user-a');
    expect(await E2eeSecureKeyStore().loadPrivateKey('user-a'), isNull);

    final after = await identities.ensureIdentity('user-a');
    expect(after.publicKeyBase64, isNot(before.publicKeyBase64));
  });
}
