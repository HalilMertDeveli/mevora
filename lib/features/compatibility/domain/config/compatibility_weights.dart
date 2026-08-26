/// Central compatibility scoring weights. Adjust here without touching UI or call sites.
abstract final class CompatibilityWeights {
  /// Profile signals from [CompatibilityEngine] strategies (interests, goals, etc.).
  static const double profile = 0.40;

  /// Relationship question answer overlap.
  static const double questions = 0.30;

  /// Spotify / music taste overlap when both users have music data.
  static const double music = 0.15;

  /// Lifestyle tag overlap (subset of profile engine, surfaced separately in UI).
  static const double lifestyle = 0.15;

  /// Minimum aligned relationship answers before "Someone is thinking like you".
  static const int hiddenCompatibilityMinAligned = 2;

  /// Minimum question compatibility score for hidden insight card.
  static const int hiddenCompatibilityMinScore = 70;

  /// Minimum overall score to highlight hidden compatibility.
  static const int hiddenCompatibilityMinOverall = 72;
}
