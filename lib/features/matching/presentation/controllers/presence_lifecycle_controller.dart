import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

/// Keeps the signed-in user's Firestore presence in sync with app lifecycle.
class PresenceLifecycleController with WidgetsBindingObserver {
  PresenceLifecycleController({
    required PresenceRepository presenceRepository,
    required AuthUidSource uidSource,
  }) : _presence = presenceRepository,
       _uidSource = uidSource;

  static const Duration heartbeatInterval = Duration(seconds: 30);

  final PresenceRepository _presence;
  final AuthUidSource _uidSource;

  Timer? _heartbeat;
  StreamSubscription<String?>? _uidSub;
  String? _uid;
  var _observing = false;
  var _foreground = false;

  void attach() {
    if (_observing) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _uidSub = _uidSource.watchUid().listen((uid) {
      unawaited(_syncUser(uid));
    }, onError: (_) {
      unawaited(_syncUser(_uidSource.currentUid));
    });
    unawaited(_syncUser(_uidSource.currentUid));
  }

  Future<void> _syncUser(String? uid) async {
    if (uid == _uid) {
      if (uid != null && _foreground) {
        await _goOnline();
      }
      return;
    }
    await _goOffline();
    _uid = uid;
    if (uid != null && _foreground) {
      await _goOnline();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_uid == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(_goOnline());
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        unawaited(_goOffline());
    }
  }

  Future<void> _goOnline() async {
    final uid = _uid;
    if (uid == null || !_foreground) {
      return;
    }
    _startHeartbeat();
    try {
      await _presence.setOnline(uid);
      // #region agent log
      // ignore: avoid_print
      print(
        '[PHOTO_DEBUG] {"sessionId":"80971b","runId":"post-fix",'
        '"hypothesisId":"H6","location":"presence_lifecycle_controller.dart",'
        '"message":"presence_set_online_ok","data":{"uidLen":${uid.length}},'
        '"timestamp":${DateTime.now().millisecondsSinceEpoch}}',
      );
      // #endregion
    } on Object catch (error) {
      // #region agent log
      // ignore: avoid_print
      print(
        '[PHOTO_DEBUG] {"sessionId":"80971b","runId":"post-fix",'
        '"hypothesisId":"H6","location":"presence_lifecycle_controller.dart",'
        '"message":"presence_set_online_error","data":{"error":"$error"},'
        '"timestamp":${DateTime.now().millisecondsSinceEpoch}}',
      );
      // #endregion
      // Chat must keep working when presence writes fail.
    }
  }

  Future<void> _goOffline() async {
    _stopHeartbeat();
    final uid = _uid;
    if (uid == null) {
      return;
    }
    try {
      await _presence.setOffline(uid);
    } on Object {
      // Best effort; stale heartbeat will mark offline for viewers.
    }
  }

  Future<void> _heartbeatNow() async {
    final uid = _uid;
    if (uid == null || !_foreground) {
      return;
    }
    try {
      await _presence.heartbeat(uid);
    } on Object {
      // Ignore transient network errors.
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    unawaited(_heartbeatNow());
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_heartbeatNow());
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    unawaited(_uidSub?.cancel());
    unawaited(_goOffline());
    _uid = null;
  }
}
