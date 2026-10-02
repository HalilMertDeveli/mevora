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

  /// Liveness only: going online and offline are written explicitly on
  /// resume and pause. The beat exists for an app that dies without a
  /// pause, and every beat is re-read by each partner's open listener.
  /// Viewers treat a beat older than PresenceSubtitle.staleAfter as
  /// offline, which must stay above two intervals.
  static const Duration heartbeatInterval = Duration(seconds: 60);

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
    // Already online with a beat running: an auth-state replay or an
    // inactive → resumed flicker (notification shade) changes nothing.
    if (uid == null || !_foreground || _heartbeat != null) {
      return;
    }
    _startHeartbeat();
    try {
      await _presence.setOnline(uid);
    } on Object {
      // Chat must keep working when presence writes fail.
    }
  }

  Future<void> _goOffline() async {
    // The beat runs exactly while this client has said it is online. Android
    // reports hidden and paused on the way out and hidden again on the way
    // back, so without this every background trip wrote offline two or three
    // times.
    final wasOnline = _heartbeat != null;
    _stopHeartbeat();
    final uid = _uid;
    if (uid == null || !wasOnline) {
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
    // No immediate beat: setOnline right after this already stamps
    // updatedAt, so a second write would only fan out twice.
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
