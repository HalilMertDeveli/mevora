import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// Which step a member still owes before the rest of the app, for the router:
///
///   new member:  basic profile (onboarding) → Humor Lab → Q1–Q15 → Picks
///   every day:   today's five (until answered or "Bugünlük geç") → the app
///
/// The server decides the stage from real facts (calibration, today's
/// answers, a recorded skip) on its own clock, so the same account always
/// lands on the same step after a restart. Any failure to load counts as
/// done: the journey can guide, never lock out.
class LearningJourneyController extends ChangeNotifier
    with WidgetsBindingObserver {
  LearningJourneyController({
    required RelationshipLearningRepository repository,
    required this.humorEnabled,
    AnalyticsProvider? analytics,
    this.loadTimeout = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _repository = repository,
       _analytics = analytics,
       _now = now ?? DateTime.now;

  final RelationshipLearningRepository _repository;
  final AnalyticsProvider? _analytics;
  final DateTime Function() _now;

  /// With the Humor Lab off, its step is simply not part of the journey.
  final bool humorEnabled;
  final Duration loadTimeout;

  JourneyStage? _stage;
  DateTime? _nextDayStartsAt;
  bool _loading = false;
  String? _uid;
  bool _disposed = false;
  bool _observing = false;
  int _generation = 0;

  /// Where the member is; done until known.
  JourneyStage get stage => _stage ?? JourneyStage.done;

  /// The very first load for this session has not answered yet.
  bool get pending => _stage == null && _loading;

  /// The route the member must finish before the rest of the app, or null.
  String? get requiredRoute => switch (stage) {
    JourneyStage.humor when humorEnabled => AppRoutes.humorCalibration,
    JourneyStage.humor || JourneyStage.daily => learningRoute,
    JourneyStage.done => null,
  };

  static const String learningRoute =
      '${AppRoutes.relationshipLearning}?source=journey';

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The member this journey belongs to. Starts the first load for them,
  /// synchronously marking the journey pending so the router holds on the
  /// splash instead of flashing the wrong screen.
  void startFor(String uid) {
    if (_uid == uid && (_stage != null || _loading)) {
      return;
    }
    _uid = uid;
    _stage = null;
    unawaited(refresh());
  }

  /// Re-reads the stage from the server. Call after sign-in and after any
  /// step changes (onboarding finished, humor calibrated or skipped, today's
  /// set completed or skipped).
  ///
  /// Listeners (the router) hear only real changes: a refresh that confirms
  /// the same stage must not make the router rebuild pages mid-flow.
  Future<void> refresh() async {
    final generation = ++_generation;
    final wasPending = pending;
    _loading = true;
    if (pending != wasPending) {
      _notify();
    }
    final result = await _repository.loadState().timeout(
      loadTimeout,
      onTimeout: () => const Err(NetworkFailure('journey-timeout')),
    );
    if (_disposed || generation != _generation) {
      return;
    }
    final previous = _stage;
    final pendingBefore = pending;
    final summary = result.valueOrNull?.summary;
    // A failure or a timeout keeps what was known, or counts as done.
    final next = summary?.journeyStage ?? previous ?? JourneyStage.done;
    _nextDayStartsAt = summary?.nextDayStartsAt ?? _nextDayStartsAt;
    _stage = next;
    _loading = false;
    _logTransition(previous, next);
    if (previous != next || pendingBefore != pending) {
      _notify();
    }
  }

  /// Coming back to the app after the server's day turned brings today's
  /// new set. Only a done journey is re-read; a step in progress is not.
  Future<void> refreshIfNewDay() async {
    final nextDay = _nextDayStartsAt;
    if (_uid == null ||
        _loading ||
        stage != JourneyStage.done ||
        nextDay == null ||
        _now().isBefore(nextDay)) {
      return;
    }
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshIfNewDay());
    }
  }

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

  /// Signed out: nothing is known about the next member.
  void clear() {
    _generation += 1;
    _uid = null;
    _stage = null;
    _nextDayStartsAt = null;
    _loading = false;
    _notify();
  }

  void _logTransition(JourneyStage? from, JourneyStage to) {
    final analytics = _analytics;
    if (analytics == null || from == to || !humorEnabled) {
      return;
    }
    final name = to == JourneyStage.humor
        ? AnalyticsEvents.humorOnboardingStarted
        : from == JourneyStage.humor
        ? AnalyticsEvents.humorOnboardingCompleted
        : null;
    if (name != null) {
      unawaited(analytics.logEvent(name).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    detachLifecycle();
    _disposed = true;
    super.dispose();
  }
}
