import 'dart:async';

import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/chat/debug/chat_debug_log.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_session_service.dart';

/// Testable port used by [E2eeBootstrapController].
abstract class E2eeIdentityBootstrapPort {
  Future<void> bootstrap(String uid);
  Future<void> reset();
}

class E2eeIdentityBootstrapAdapter implements E2eeIdentityBootstrapPort {
  E2eeIdentityBootstrapAdapter([E2eeIdentityService? identityService])
    : _identity = identityService ?? E2eeIdentityService();

  final E2eeIdentityService _identity;

  @override
  Future<void> bootstrap(String uid) async {
    await _identity.ensureIdentity(uid);
  }

  @override
  Future<void> reset() => _identity.clearLocalIdentity();
}

/// Publishes the user's E2EE public key as soon as they sign in so peers can
/// establish encrypted sessions before the first message is sent.
class E2eeBootstrapController {
  E2eeBootstrapController({
    required AuthUidSource uidSource,
    E2eeIdentityBootstrapPort? identityBootstrap,
  }) : _uidSource = uidSource,
       _identity = identityBootstrap ?? E2eeIdentityBootstrapAdapter();

  final AuthUidSource _uidSource;
  final E2eeIdentityBootstrapPort _identity;

  StreamSubscription<String?>? _uidSub;
  String? _uid;

  void attach() {
    if (_uidSub != null) {
      return;
    }
    _uidSub = _uidSource.watchUid().listen(
      (uid) => unawaited(_syncUser(uid)),
      onError: (_) => unawaited(_syncUser(_uidSource.currentUid)),
    );
    unawaited(_syncUser(_uidSource.currentUid));
  }

  Future<void> _syncUser(String? uid) async {
    if (uid == _uid) {
      return;
    }
    if (_uid != null) {
      await _identity.reset();
      ChatDebugLog.event('e2ee_identity_cleared');
    }
    _uid = uid;
    if (uid == null) {
      return;
    }
    try {
      await _identity.bootstrap(uid);
      ChatDebugLog.event(
        'e2ee_identity_ready',
        fields: {'uid': uid},
      );
    } on Object {
      ChatDebugLog.event('e2ee_identity_failed', fields: {'uid': uid});
    }
  }

  void dispose() {
    unawaited(_uidSub?.cancel());
    _uidSub = null;
    _uid = null;
  }
}
