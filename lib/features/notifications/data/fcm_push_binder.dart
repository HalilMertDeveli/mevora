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
  StreamSubscription<Map<String, dynamic>>? _openedSub;
  StreamSubscription<Map<String, dynamic>>? _foregroundSub;
  var _attached = false;

  Future<void> attach() async {
    if (_attached) {
      return;
    }
    _attached = true;
    await _messaging.requestPermission();
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

  Future<void> _registerCurrentToken() async {
    final result = await _messaging.getToken();
    final token = result.valueOrNull;
    if (token != null) {
      await _registerToken(token);
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
    unawaited(_tokenSub?.cancel());
    unawaited(_openedSub?.cancel());
    unawaited(_foregroundSub?.cancel());
  }
}
