import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// Which first-run step a NEW member still owes, for the router:
///
///   basic profile (onboarding) → Humor Lab → Relationship Learning → Picks
///
/// The server decides the stage from real facts (calibration, answers, a
/// recorded humor skip), so the same account always lands on the same step
/// after a restart. Existing members are always [JourneyStage.done]. Any
/// failure to load counts as done: the journey can guide, never lock out.
class LearningJourneyController extends ChangeNotifier {
  LearningJourneyController({
    required RelationshipLearningRepository repository,
    required this.humorEnabled,
    AnalyticsProvider? analytics,
    this.loadTimeout = const Duration(seconds: 8),
  }) : _repository = repository,
       _analytics = analytics;

  final RelationshipLearningRepository _repository;
  final AnalyticsProvider? _analytics;

  /// With the Humor Lab off, its step is simply not part of the journey.
  final bool humorEnabled;
  final Duration loadTimeout;

  JourneyStage? _stage;
  bool _loading = false;
  String? _uid;
  bool _disposed = false;
  int _generation = 0;

  /// Where the member is; done until known.
  JourneyStage get stage => _stage ?? JourneyStage.done;

  /// The very first load for this session has not answered yet.
  bool get pending => _stage == null && _loading;

  /// The route the member must finish before the rest of the app, or null.
  String? get requiredRoute => switch (stage) {
    JourneyStage.humor when humorEnabled => AppRoutes.humorCalibration,
    JourneyStage.humor || JourneyStage.learning => learningRoute,
    JourneyStage.done => null,
  };

  static const String learningRoute =
      '${AppRoutes.relationshipLearning}?source=journey';

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The member this journey belongs to. Starts the first load for a new
  /// member, synchronously marking the journey pending so the router holds
  /// on the splash instead of flashing the wrong screen.
  void startFor(String uid) {
    if (_uid == uid && (_stage != null || _loading)) {
      return;
    }
    _uid = uid;
    _stage = null;
    unawaited(refresh());
  }

  /// Re-reads the stage from the server. Call after sign-in and after any
  /// step changes (onboarding finished, humor calibrated or skipped, the
  /// initial questions completed).
  Future<void> refresh() async {
    final generation = ++_generation;
    _loading = true;
    _notify();
    final result = await _repository.loadState().timeout(
      loadTimeout,
      onTimeout: () => const Err(NetworkFailure('journey-timeout')),
    );
    if (_disposed || generation != _generation) {
      return;
    }
    final previous = _stage;
    // A failure or a timeout keeps what was known, or counts as done.
    final next =
        result.valueOrNull?.summary.journeyStage ??
        previous ??
        JourneyStage.done;
    _stage = next;
    _loading = false;
    _logTransition(previous, next);
    _notify();
  }

  /// Signed out: nothing is known about the next member.
  void clear() {
    _generation += 1;
    _uid = null;
    _stage = null;
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
    _disposed = true;
    super.dispose();
  }
}
