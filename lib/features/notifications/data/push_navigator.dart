import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:mevora/core/routing/app_routes.dart';

/// Takes a member to the screen a notification points at.
///
/// Two things a plain `router.go(location)` got wrong:
///
/// * A conversation opened that way was the only page on the stack, so it had
///   no back button and system Back left the app. A conversation is opened on
///   top of the Matches tab instead.
/// * On a cold start the tap arrives while the app is still on the splash
///   screen. The router's redirect refuses the destination, and by the time
///   the session is restored nobody remembers it. The destination is kept
///   until the router lets it through — after the splash, after sign-in, after
///   a gate the member has to pass first — or until it is too old to matter.
class PushNavigator {
  PushNavigator({
    required this.router,
    DateTime Function()? clock,
    this.pendingLifetime = const Duration(minutes: 5),
  }) : _clock = clock ?? DateTime.now;

  final GoRouter router;
  final DateTime Function() _clock;

  /// How long a destination the router keeps refusing is worth keeping.
  final Duration pendingLifetime;

  String? _pending;
  DateTime? _pendingSince;

  /// Where the app was when the router refused the last attempt. Nothing has
  /// changed while it is still there, so trying again would only loop.
  String? _refusedAt;
  var _navigating = false;
  var _listening = false;

  /// Set when an attempt failed only because the app moved meanwhile.
  var _movedOn = false;

  /// Immediate retries left for the current destination; route changes still
  /// trigger further attempts once these are used up.
  var _retriesLeft = _maxImmediateRetries;
  static const _maxImmediateRetries = 5;

  /// The destination still waiting to be opened, if any.
  String? get pendingLocation => _pending;

  void open(String location) {
    _pending = location;
    _pendingSince = _clock();
    _refusedAt = null;
    _movedOn = false;
    _retriesLeft = _maxImmediateRetries;
    unawaited(_drain());
  }

  void dispose() {
    _clear();
  }

  Future<void> _drain() async {
    final target = _pending;
    if (target == null || _navigating) {
      return;
    }
    final since = _pendingSince;
    if (since == null || _clock().difference(since) > pendingLifetime) {
      _clear();
      return;
    }
    final from = _currentLocation();
    if (from == target) {
      _clear();
      return;
    }
    if (from == _refusedAt) {
      _listen();
      return;
    }

    _navigating = true;
    try {
      final parent = _parentOf(target);
      if (parent != null && from != parent) {
        router.go(parent);
        await _settled(() => _currentLocation() != from);
        if (_currentLocation() != parent) {
          _refuse(from);
          return;
        }
      }
      if (parent != null) {
        unawaited(router.push<void>(target));
      } else {
        router.go(target);
      }
      await _settled(() => _currentLocation() == target);
      if (_pending != target) {
        // A newer notification replaced this one meanwhile.
        return;
      }
      if (_currentLocation() == target) {
        _clear();
      } else {
        _refuse(parent ?? from);
      }
    } finally {
      _navigating = false;
      // A newer destination arrived, or the app moved on by itself while this
      // attempt was in flight: go again from where things stand now.
      if (_pending != null && (_pending != target || _movedOn)) {
        _movedOn = false;
        unawaited(_drain());
      }
    }
  }

  /// The page a destination belongs under, so Back has somewhere to go.
  static String? _parentOf(String location) {
    if (location.startsWith('/chat/')) {
      return AppRoutes.matches;
    }
    return null;
  }

  /// Records a refused attempt made while the app was at [attemptedFrom].
  ///
  /// On a cold start the app leaves the splash on its own while the attempt is
  /// still in flight. The attempt was judged from the splash, so ending up
  /// somewhere else says nothing about that place: it is tried again from
  /// there straight away instead of being remembered as refused.
  void _refuse(String attemptedFrom) {
    _listen();
    if (_currentLocation() != attemptedFrom && _retriesLeft > 0) {
      _retriesLeft -= 1;
      _movedOn = true;
      return;
    }
    _refusedAt = _currentLocation();
  }

  void _listen() {
    if (_listening) {
      return;
    }
    _listening = true;
    router.routerDelegate.addListener(_onRouteChanged);
  }

  void _onRouteChanged() {
    unawaited(_drain());
  }

  void _clear() {
    _pending = null;
    _pendingSince = null;
    _refusedAt = null;
    _movedOn = false;
    if (_listening) {
      _listening = false;
      router.routerDelegate.removeListener(_onRouteChanged);
    }
  }

  String _currentLocation() {
    if (router.routerDelegate.currentConfiguration.isEmpty) {
      return '';
    }
    return router.state.uri.path;
  }

  /// Route changes are applied asynchronously; give one a moment to land.
  Future<void> _settled(bool Function() done) async {
    for (var i = 0; i < 20 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}
