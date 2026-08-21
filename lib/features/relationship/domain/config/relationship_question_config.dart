import 'package:flutter/foundation.dart';

/// Relationship question trigger timings.
///
/// - Spontaneous offer while on Discovery: every [productionInterval]
///   (debug builds use [debugInterval]).
/// - Survey finished / offer dismissed without taking a match: wait
///   [declinedCooldown], then offer again.
/// - Match taken (open chat): wait [matchedCooldown] with no survey.
abstract final class RelationshipQuestionConfig {
  static const Duration productionInterval = Duration(minutes: 30);
  static const Duration debugInterval = Duration(seconds: 30);
  static const Duration idleTimeout = Duration(seconds: 20);
  static const Duration declinedCooldown = Duration(minutes: 3);
  static const Duration matchedCooldown = Duration(minutes: 30);
  static const int questionsPerSession = 3;
  static const int resultLimit = 1;
  static const double maxDistanceKm = 100;

  /// Optional local override: `--dart-define=RELATIONSHIP_QUESTION_DEBUG=true`.
  static const bool forceDebugInterval = bool.fromEnvironment(
    'RELATIONSHIP_QUESTION_DEBUG',
  );

  /// Debug-only: let the offer fire even with existing matches / cooldown.
  /// Production always enforces those gates. Tests should pass
  /// `enforceOfferGates: true` on [RelationshipController].
  static bool get bypassOfferGates => isDebugInterval;

  static Duration get interval {
    if (kReleaseMode) {
      return productionInterval;
    }
    if (kDebugMode || forceDebugInterval) {
      return debugInterval;
    }
    return productionInterval;
  }

  static bool get isDebugInterval => interval == debugInterval;

  /// @Deprecated Use [declinedCooldown] or [matchedCooldown].
  static const Duration offerCooldown = declinedCooldown;

  static Duration cooldownFor({required bool matchTaken}) {
    return matchTaken ? matchedCooldown : declinedCooldown;
  }
}
