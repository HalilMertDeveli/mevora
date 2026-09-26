import 'package:flutter/foundation.dart';

/// Relationship / matching-event timings.
///
/// Spontaneous offer while on Discovery uses [matchingEventDuration]
/// (alias of [productionInterval]). Change this single constant to retune
/// event length (3 → 5 → 10 → 15 minutes) without hunting magic numbers.
abstract final class RelationshipQuestionConfig {
  /// Spontaneous relationship-test offer on Discovery. Off until the feature
  /// is reworked; re-enable locally with
  /// `--dart-define=RELATIONSHIP_AUTO_OFFER=true`.
  static const bool autoOfferEnabled = bool.fromEnvironment(
    'RELATIONSHIP_AUTO_OFFER',
  );

  /// Configurable matching-event length (default: 3 minutes).
  static const Duration matchingEventDuration = Duration(minutes: 3);

  /// @nodoc Keep older call sites compiling — same value as [matchingEventDuration].
  static const Duration productionInterval = matchingEventDuration;

  static const Duration debugInterval = Duration(seconds: 30);
  static const Duration idleTimeout = Duration(seconds: 20);
  static const Duration declinedCooldown = Duration(minutes: 3);
  static const Duration matchedCooldown = Duration(minutes: 30);

  /// Recent messages within this window count as an "active conversation"
  /// and temporarily exclude the user from new matching events.
  static const Duration activeConversationWindow = Duration(minutes: 30);

  /// After this many completed events, ask whether to continue.
  static const int eventsBeforeContinuePrompt = 5;

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
