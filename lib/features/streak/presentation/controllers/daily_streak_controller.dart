import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/streak/data/streak_analytics.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/domain/repositories/daily_streak_repository.dart';

/// The uid whose streak should be shown, given the auth state — or [current]
/// while auth is between states.
///
/// Only a member who has finished onboarding has a streak, which is the same
/// reading the router makes before letting someone into the app. Transient
/// states (initialising, signing in, an OTP in flight) keep whoever is bound
/// so a token refresh or a resume does not blank the indicator.
String? streakMemberUid(AuthStatus status, {String? current}) {
  return switch (status) {
    Authenticated(:final user) =>
      user.onboardingCompleted || user.profileCompleted ? user.id : null,
    Unauthenticated() || NeedsOnboarding() || AuthenticationError() => null,
    AuthInitializing() ||
    Authenticating() ||
    PhoneCodeSent() ||
    PhoneVerificationRequired() => current,
  };
}

/// Asks the backend to record today's visit when a member enters or returns
/// to the app, and holds the last streak it confirmed.
///
/// It never counts anything itself. A failed request keeps the last known
/// streak on screen, is retried a few times with backoff and again on the
/// next resume, and never blocks the app. The server is idempotent per day,
/// so a retry is harmless; this class only keeps them from piling up.
class DailyStreakController extends ChangeNotifier with WidgetsBindingObserver {
  DailyStreakController({
    required DailyStreakRepository repository,
    StreakAnalytics analytics = const StreakAnalytics(null),
    AppLogger? logger,
    DateTime Function()? clock,
    this.minInterval = const Duration(seconds: 20),
    this.retryDelays = const [
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
    ],
  }) : _repository = repository,
       _analytics = analytics,
       _logger = logger,
       _clock = clock ?? DateTime.now;

  final DailyStreakRepository _repository;
  final StreakAnalytics _analytics;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  /// Lifecycle events closer together than this do not call the backend.
  final Duration minInterval;

  /// Automatic retries after a failure. Later ones happen on resume.
  final List<Duration> retryDelays;

  String? _uid;
  DailyStreak? _streak;
  DailyCheckInResult? _celebration;
  bool _failed = false;
  int _generation = 0;
  Future<void>? _inFlight;
  DateTime? _lastAttemptAt;
  String? _confirmedLocalDay;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _observing = false;
  bool _disposed = false;

  String? get uid => _uid;

  /// The last streak the backend confirmed for [uid], or null when there is
  /// none to show (signed out, not yet loaded, not an active member).
  DailyStreak? get streak => _streak;

  /// True after a failed refresh until the next success. Nothing in the UI
  /// has to react to it; the last known streak stays as it was.
  bool get hasError => _failed;

  /// A credited day waiting to be celebrated. Set only when the backend
  /// awarded a new day on this call.
  DailyCheckInResult? get pendingCelebration => _celebration;

  /// Hands the pending celebration to the one caller that will show it.
  DailyCheckInResult? takeCelebration() {
    final result = _celebration;
    _celebration = null;
    return result;
  }

  StreakAnalytics get analytics => _analytics;

  void attachLifecycle() {
    if (_observing || _disposed) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  void detachLifecycle() {
    if (!_observing) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  /// Switches to [uid] (null when nobody eligible is signed in). A different
  /// user drops everything held for the previous one — including a request
  /// still in flight — before anything of the new one is fetched.
  void bindUser(String? uid) {
    if (uid == _uid || _disposed) {
      return;
    }
    _generation++;
    _uid = uid;
    _streak = null;
    _celebration = null;
    _failed = false;
    _inFlight = null;
    _lastAttemptAt = null;
    _confirmedLocalDay = null;
    _cancelRetry();
    _retryCount = 0;
    notifyListeners();
    if (uid != null) {
      unawaited(refresh(force: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  /// Checks in with the backend.
  ///
  /// Without [force], this is skipped when today (by the device's calendar)
  /// was already confirmed or an attempt was made moments ago. The device
  /// clock only decides *whether to ask*; the server decides the answer.
  Future<void> refresh({bool force = false}) {
    final uid = _uid;
    if (uid == null || _disposed) {
      return Future<void>.value();
    }
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final now = _clock();
    if (!force) {
      if (!_failed && _confirmedLocalDay == _localDayKey(now)) {
        return Future<void>.value();
      }
      final last = _lastAttemptAt;
      if (last != null && now.difference(last).abs() < minInterval) {
        return Future<void>.value();
      }
    }
    _lastAttemptAt = now;
    final future = _checkIn(_generation, now);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<void> _checkIn(int generation, DateTime now) async {
    try {
      final result = await _repository.checkIn(
        timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
      );
      if (generation != _generation || _disposed) {
        return;
      }
      _cancelRetry();
      _retryCount = 0;
      _failed = false;
      _confirmedLocalDay = _localDayKey(now);
      _streak = result.status == CheckInStatus.ineligible
          ? null
          : result.streak;
      if (result.credited) {
        _celebration = result;
        _analytics.checkIn(result);
      }
      notifyListeners();
    } on Object catch (error) {
      if (generation != _generation || _disposed) {
        return;
      }
      // Keep whatever was last confirmed: an unreachable backend says
      // nothing about the streak, and must never read as a broken one.
      _failed = true;
      _logger?.warning('Daily streak check-in failed', error: error);
      _scheduleRetry();
      notifyListeners();
    }
  }

  void _scheduleRetry() {
    _cancelRetry();
    if (_retryCount >= retryDelays.length) {
      return;
    }
    final delay = retryDelays[_retryCount++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(refresh(force: true));
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  static String _localDayKey(DateTime now) {
    final local = now.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRetry();
    detachLifecycle();
    super.dispose();
  }
}
