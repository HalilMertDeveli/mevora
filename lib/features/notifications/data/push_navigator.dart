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

  /// Where the router sent the last attempt back to. Nothing has changed
  /// while the app is still there, so trying again would only loop.
  String? _refusedAt;
  var _navigating = false;
  var _listening = false;

  /// The destination still waiting to be opened, if any.
  String? get pendingLocation => _pending;

  void open(String location) {
    _pending = location;
    _pendingSince = _clock();
    _refusedAt = null;
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
          _refuse();
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
        _refuse();
      }
    } finally {
      _navigating = false;
    }
    if (_pending != null && _pending != target) {
      unawaited(_drain());
    }
  }

  /// The page a destination belongs under, so Back has somewhere to go.
  static String? _parentOf(String location) {
    if (location.startsWith('/chat/')) {
      return AppRoutes.matches;
    }
    return null;
  }

  void _refuse() {
    _refusedAt = _currentLocation();
    _listen();
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
