import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';
import 'package:mevora/features/notifications/domain/push_route_resolver.dart';

/// Composition-root FCM binder. Widgets never call FirebaseMessaging.
class FcmPushBinder {
  FcmPushBinder({
    required this.router,
    required this.services,
    FirebaseMessagingDataSource? messaging,
  }) : _messaging = messaging ?? FirebaseMessagingDataSource();

  final GoRouter router;
  final SocialServices services;
  final FirebaseMessagingDataSource _messaging;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<Map<String, dynamic>>? _openedSub;
  StreamSubscription<Map<String, dynamic>>? _foregroundSub;
  var _attached = false;

  /// The member the current token was last registered for (or is being
  /// registered for). Cleared on sign-out, so the next sign-in writes again.
  String? _registeredUid;

  Future<void> attach() async {
    if (_attached) {
      return;
    }
    _attached = true;
    // Never request OS notification permission on launch. Request it from
    // PermissionService when the user opens a notifications feature.
    //
    // The token belongs to whoever is signed in: a member who signs in (or
    // switches account) after launch is registered here, not at the next
    // cold start.
    _uidSub = services.uidSource.watchUid().listen(_onUid, onError: (_) {});
    await _registerCurrentToken();
    _tokenSub = _messaging.watchTokenRefresh().listen(_registerToken);
    _openedSub = _messaging.watchOpenedApp().listen(_open);
    _foregroundSub = _messaging.watchForegroundMessage().listen((data) {
      final type = data['type']?.toString();
      if (type == 'incomingCall' || type == 'incoming_call') {
        _open(data);
      }
    });
    final initial = await _messaging.initialMessage();
    if (initial != null) {
      _open(initial);
    }
  }

  Future<void> registerCurrentToken() => _registerCurrentToken();

  void _onUid(String? uid) {
    if (uid == _registeredUid) {
      return;
    }
    if (uid == null) {
      _registeredUid = null;
      return;
    }
    unawaited(_registerForSignIn());
  }

  Future<void> _registerForSignIn() async {
    try {
      await _registerCurrentToken();
    } on Object {
      // Best-effort: the next auth change, token refresh or launch retries.
    }
  }

  Future<void> _registerCurrentToken() async {
    // Claimed before the first await, so an auth emission for the same member
    // that lands while the token is being read does not register twice.
    final uid = services.uidSource.currentUid;
    _registeredUid = uid;
    final result = await _messaging.getToken();
    final token = result.valueOrNull;
    if (token == null || uid == null) {
      return;
    }
    if (services.uidSource.currentUid != uid) {
      // The member changed meanwhile; their own auth emission registers them.
      return;
    }
    try {
      await _messaging.registerDevice(uid: uid, token: token);
    } on Object {
      if (_registeredUid == uid) {
        _registeredUid = null;
      }
      rethrow;
    }
  }

  Future<void> _registerToken(String token) async {
    final uid = services.uidSource.currentUid;
    if (uid == null) {
      return;
    }
    await _messaging.registerDevice(uid: uid, token: token);
  }

  void _open(Map<String, dynamic> data) {
    final location = PushRouteResolver.fromData(data);
    if (location != null) {
      router.go(location);
    }
  }

  void dispose() {
    unawaited(_uidSub?.cancel());
    unawaited(_tokenSub?.cancel());
    unawaited(_openedSub?.cancel());
    unawaited(_foregroundSub?.cancel());
  }
}
