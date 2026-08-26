import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:mevora/core/services/app_logger.dart';

/// Restores Auth tokens and Firestore connectivity after long idle / resume.
class SessionRecoveryController with WidgetsBindingObserver {
  SessionRecoveryController({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AppLogger? logger,
  }) : _auth = auth,
       _firestore = firestore,
       _logger = logger,
       _useDefaults = auth == null && firestore == null;

  /// Test constructor that never touches Firebase singletons.
  SessionRecoveryController.detached({AppLogger? logger})
    : _auth = null,
      _firestore = null,
      _logger = logger,
      _useDefaults = false;

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final AppLogger? _logger;
  final bool _useDefaults;

  final _refreshController = StreamController<DateTime>.broadcast();
  bool _attached = false;
  bool _recovering = false;
  DateTime? _lastRecoveryAt;

  /// Fires after a successful resume recovery so screens can soft-refresh.
  Stream<DateTime> get onRecovered => _refreshController.stream;

  FirebaseAuth? get _resolvedAuth {
    if (_auth != null) {
      return _auth;
    }
    if (!_useDefaults) {
      return null;
    }
    try {
      return FirebaseAuth.instance;
    } on Object {
      return null;
    }
  }

  FirebaseFirestore? get _resolvedFirestore {
    if (_firestore != null) {
      return _firestore;
    }
    if (!_useDefaults) {
      return null;
    }
    try {
      return FirebaseFirestore.instance;
    } on Object {
      return null;
    }
  }

  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(recover(reason: 'resume'));
    }
  }

  /// Force-refresh ID token + ensure Firestore network is enabled.
  Future<void> recover({String reason = 'manual'}) async {
    if (_recovering) {
      return;
    }
    final last = _lastRecoveryAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _recovering = true;
    try {
      final auth = _resolvedAuth;
      final user = auth?.currentUser;
      if (user != null) {
        try {
          await user.getIdToken(true);
        } on Object catch (error, stackTrace) {
          _logger?.warning(
            'Auth token refresh failed on $reason',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      final firestore = _resolvedFirestore;
      if (firestore != null) {
        try {
          await firestore.enableNetwork();
        } on Object catch (error, stackTrace) {
          _logger?.warning(
            'Firestore enableNetwork failed on $reason',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _lastRecoveryAt = DateTime.now();
      if (!_refreshController.isClosed) {
        _refreshController.add(_lastRecoveryAt!);
      }
    } finally {
      _recovering = false;
    }
  }

  void dispose() {
    detach();
    unawaited(_refreshController.close());
  }
}
