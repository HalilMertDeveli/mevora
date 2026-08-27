import 'package:flutter/foundation.dart';

/// Relationship / matching-event timings.
///
/// Product model:
/// - First-time users: one-shot **initial** personality test (no dwell).
/// - After that: **Mevora Hour** only (Europe/Istanbul hourly rounds).
/// - Legacy Discover dwell (3 minutes) is permanently disabled in production.
abstract final class RelationshipQuestionConfig {
  /// Mevora Hour (Europe/Istanbul hourly rounds) is the post-initial trigger.
  static const bool hourlyGlobalMatchingGame = true;

  /// Kill switch for the old "N minutes on Discover" offer timer.
  /// Must stay false in production. Tests may override via controller ctor.
  static const bool legacyDwellOffersEnabled = false;

  /// @Deprecated Legacy dwell length — cooldown aliases / debug only.
  /// Does **not** open personality offers when [legacyDwellOffersEnabled] is false.
  static const Duration matchingEventDuration = Duration(minutes: 3);

  /// @nodoc Keep older call sites compiling — same value as [matchingEventDuration].
  static const Duration productionInterval = matchingEventDuration;

  static const Duration debugInterval = Duration(seconds: 30);
  static const Duration idleTimeout = Duration(seconds: 20);
  static const Duration declinedCooldown = Duration(minutes: 3);
  static const Duration matchedCooldown = Duration(minutes: 30);

  /// Recent messages within this window count as an "active conversation"
  /// (legacy dwell gate only).
  static const Duration activeConversationWindow = Duration(minutes: 30);

  /// After this many completed events, ask whether to continue (legacy only).
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

/// Which product flow opened the current offer / session.
enum RelationshipOfferKind {
  /// One-time post-onboarding personality test (`matchingEventCount == 0`).
  initial,

  /// Mevora Hour hourly Istanbul round.
  hourly,
}
