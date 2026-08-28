/// Signal categories for structured Why You Matched reasons.
///
/// Only categories backed by Phase 0 data sources are listed.
enum WhyYouMatchedCategory {
  humor,
  music,
  interests,
  lifestyle,
  preferences,
  communication,
  distance,
  relationship,
  questions,
}

extension WhyYouMatchedCategoryX on WhyYouMatchedCategory {
  String get wireValue => name;

  String get defaultIconName => switch (this) {
        WhyYouMatchedCategory.humor => 'mood',
        WhyYouMatchedCategory.music => 'music_note',
        WhyYouMatchedCategory.interests => 'interests',
        WhyYouMatchedCategory.lifestyle => 'self_improvement',
        WhyYouMatchedCategory.preferences => 'tune',
        WhyYouMatchedCategory.communication => 'forum',
        WhyYouMatchedCategory.distance => 'place',
        WhyYouMatchedCategory.relationship => 'favorite',
        WhyYouMatchedCategory.questions => 'psychology',
      };

  static WhyYouMatchedCategory? tryParse(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    for (final value in WhyYouMatchedCategory.values) {
      if (value.name == key) {
        return value;
      }
    }
    return null;
  }
}

/// Evidence-backed strength of a single match reason.
enum WhyYouMatchedStrength {
  weak,
  moderate,
  strong,
}

extension WhyYouMatchedStrengthX on WhyYouMatchedStrength {
  static WhyYouMatchedStrength fromScore(int score) {
    if (score >= 75) {
      return WhyYouMatchedStrength.strong;
    }
    if (score >= 50) {
      return WhyYouMatchedStrength.moderate;
    }
    return WhyYouMatchedStrength.weak;
  }
}
