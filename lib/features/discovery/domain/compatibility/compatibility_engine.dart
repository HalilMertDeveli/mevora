import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

class DiscoveryPreferences {
  const DiscoveryPreferences({
    this.minAge = 18,
    this.maxAge = 99,
    this.maxDistanceKm = 80,
  });

  final int minAge;
  final int maxAge;
  final double maxDistanceKm;
}

class CompatibilityContext {
  const CompatibilityContext({
    required this.viewer,
    required this.candidate,
    this.preferences = const DiscoveryPreferences(),
    this.distanceKm,
  });

  final UserProfile viewer;
  final UserProfile candidate;
  final DiscoveryPreferences preferences;

  /// Server-derived kilometers. Exact coordinates never enter this context.
  final double? distanceKm;
}

class CompatibilityResult {
  const CompatibilityResult({
    required this.score,
    required this.sharedInterests,
    required this.reasons,
    this.sharedLanguages = const [],
    this.sharedHobbies = const [],
    this.categoryScores = const {},
  });

  /// 0–100 inclusive.
  final int score;
  final List<String> sharedInterests;
  final List<String> reasons;
  final List<String> sharedLanguages;
  final List<String> sharedHobbies;

  /// Raw strategy id → 0–100 when data was available.
  final Map<String, int> categoryScores;
}

/// Weighted scoring strategy. Add an AI strategy later without changing callers.
abstract class CompatibilityStrategy {
  String get id;

  double get weight;

  /// When false, this dimension is excluded from the weighted average.
  bool applies(CompatibilityContext context);

  /// Raw score in 0–1. Only called when [applies] is true.
  double score(CompatibilityContext context);

  String? reason(CompatibilityContext context);
}

abstract final class CompatibilityScoring {
  static Set<String> normalizedSet(Iterable<String> values) {
    return values.map(normalize).where((value) => value.isNotEmpty).toSet();
  }

  static double jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0.5;
    }
    final shared = a.intersection(b);
    final union = a.union(b);
    if (union.isEmpty) {
      return 0.5;
    }
    return (shared.length / union.length).clamp(0, 1);
  }

  static String? normalizeRelationshipGoal(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final key = raw.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
    return switch (key) {
      'longterm' => OnboardingRelationshipGoal.longTerm,
      'shortterm' => OnboardingRelationshipGoal.shortTerm,
      'casual' => OnboardingRelationshipGoal.shortTerm,
      'friendship' => OnboardingRelationshipGoal.friendship,
      'notsure' => OnboardingRelationshipGoal.notSure,
      'figuringout' => OnboardingRelationshipGoal.notSure,
      'prefernottosay' => OnboardingRelationshipGoal.preferNotToSay,
      _ => raw.trim().toLowerCase(),
    };
  }

  static int? habitLevel(String? value) {
    return switch (value) {
      OnboardingLifestyleOption.never => 0,
      OnboardingLifestyleOption.sometimes => 1,
      OnboardingLifestyleOption.regularly => 2,
      OnboardingLifestyleOption.daily => 3,
      _ => null,
    };
  }

  static double partnerHabitScore(int habitLevel, String partnerPref) {
    return switch (partnerPref) {
      PartnerPreference.noIssue => 1,
      PartnerPreference.prefer => switch (habitLevel) {
          0 || 1 => 1,
          2 => 0.55,
          _ => 0.25,
        },
      PartnerPreference.preferNot => switch (habitLevel) {
          0 => 1,
          1 => 0.45,
          _ => 0.1,
        },
      PartnerPreference.never => habitLevel == 0 ? 1 : 0,
      _ => 0.5,
    };
  }

  static double childrenAlignment(String? a, String? b) {
    if (a == null || b == null) {
      return 0.5;
    }
    if (a == b) {
      return 1;
    }
    final flexible = {ChildrenPreference.maybe, ChildrenPreference.undecided};
    if (flexible.contains(a) || flexible.contains(b)) {
      return 0.75;
    }
    if ((a == ChildrenPreference.yes && b == ChildrenPreference.no) ||
        (a == ChildrenPreference.no && b == ChildrenPreference.yes)) {
      return 0.15;
    }
    return 0.5;
  }

  static double partnerChildrenScore(String? partnerPref, String? otherPref) {
    if (partnerPref == null || otherPref == null) {
      return -1;
    }
    return switch (partnerPref) {
      PartnerPreference.noIssue => 1,
      PartnerPreference.prefer => childrenAlignment(
          ChildrenPreference.yes,
          otherPref,
        ),
      PartnerPreference.preferNot => childrenAlignment(
          ChildrenPreference.no,
          otherPref,
        ),
      PartnerPreference.never => otherPref == ChildrenPreference.no ? 1 : 0.1,
      _ => 0.5,
    };
  }

  static String normalize(String value) => value.trim().toLowerCase();
}

class InterestStrategy implements CompatibilityStrategy {
  const InterestStrategy({this.weight = 0.18});

  @override
  final double weight;

  @override
  String get id => 'interests';

  @override
  bool applies(CompatibilityContext context) {
    return context.viewer.interests.isNotEmpty &&
        context.candidate.interests.isNotEmpty;
  }

  @override
  double score(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizedSet(context.viewer.interests);
    final candidate =
        CompatibilityScoring.normalizedSet(context.candidate.interests);
    return CompatibilityScoring.jaccard(viewer, candidate);
  }

  @override
  String? reason(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizedSet(context.viewer.interests);
    final shared = context.candidate.interests
        .where((interest) => viewer.contains(CompatibilityScoring.normalize(interest)))
        .toList();
    if (shared.isEmpty) {
      return null;
    }
    return 'You both like ${shared.take(3).join(', ')}';
  }
}

class LanguageStrategy implements CompatibilityStrategy {
  const LanguageStrategy({this.weight = 0.10});

  @override
  final double weight;

  @override
  String get id => 'languages';

  @override
  bool applies(CompatibilityContext context) {
    return context.viewer.languages.isNotEmpty &&
        context.candidate.languages.isNotEmpty;
  }

  @override
  double score(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizedSet(context.viewer.languages);
    final candidate =
        CompatibilityScoring.normalizedSet(context.candidate.languages);
    return CompatibilityScoring.jaccard(viewer, candidate);
  }

  @override
  String? reason(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizedSet(context.viewer.languages);
    final shared = context.candidate.languages
        .where((lang) => viewer.contains(CompatibilityScoring.normalize(lang)))
        .toList();
    if (shared.isEmpty) {
      return null;
    }
    return 'You both speak ${shared.take(3).join(', ')}';
  }
}

class HobbyStrategy implements CompatibilityStrategy {
  const HobbyStrategy({this.weight = 0.05});

  @override
  final double weight;

  @override
  String get id => 'hobbies';

  @override
  bool applies(CompatibilityContext context) {
    return context.viewer.hobbies.isNotEmpty &&
        context.candidate.hobbies.isNotEmpty;
  }

  @override
  double score(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizedSet(context.viewer.hobbies);
    final candidate =
        CompatibilityScoring.normalizedSet(context.candidate.hobbies);
    return CompatibilityScoring.jaccard(viewer, candidate);
  }

  @override
  String? reason(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizedSet(context.viewer.hobbies);
    final shared = context.candidate.hobbies
        .where((hobby) => viewer.contains(CompatibilityScoring.normalize(hobby)))
        .toList();
    if (shared.isEmpty) {
      return null;
    }
    return 'You both enjoy ${shared.take(3).join(', ')}';
  }
}

class RelationshipGoalStrategy implements CompatibilityStrategy {
  const RelationshipGoalStrategy({this.weight = 0.20});

  @override
  final double weight;

  @override
  String get id => 'relationshipGoal';

  @override
  bool applies(CompatibilityContext context) {
    return CompatibilityScoring.normalizeRelationshipGoal(
              context.viewer.relationshipGoal,
            ) !=
            null &&
        CompatibilityScoring.normalizeRelationshipGoal(
              context.candidate.relationshipGoal,
            ) !=
            null;
  }

  @override
  double score(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizeRelationshipGoal(
      context.viewer.relationshipGoal,
    );
    final candidate = CompatibilityScoring.normalizeRelationshipGoal(
      context.candidate.relationshipGoal,
    );
    if (viewer == null || candidate == null) {
      return 0.5;
    }
    return viewer == candidate ? 1 : 0.35;
  }

  @override
  String? reason(CompatibilityContext context) {
    final viewer = CompatibilityScoring.normalizeRelationshipGoal(
      context.viewer.relationshipGoal,
    );
    final candidate = CompatibilityScoring.normalizeRelationshipGoal(
      context.candidate.relationshipGoal,
    );
    if (viewer != null && viewer == candidate) {
      return 'You want the same kind of relationship';
    }
    return null;
  }
}

class ValuesStrategy implements CompatibilityStrategy {
  const ValuesStrategy({this.weight = 0.10});

  @override
  final double weight;

  @override
  String get id => 'values';

  @override
  bool applies(CompatibilityContext context) {
    return _pairScores(context).isNotEmpty;
  }

  @override
  double score(CompatibilityContext context) {
    final scores = _pairScores(context);
    if (scores.isEmpty) {
      return 0.5;
    }
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  @override
  String? reason(CompatibilityContext context) => null;

  List<double> _pairScores(CompatibilityContext context) {
    final scores = <double>[];
    _addHabitScores(scores, context.viewer.lifestyleProfile, context.candidate.lifestyleProfile);
    _addHabitScores(scores, context.candidate.lifestyleProfile, context.viewer.lifestyleProfile);
    _addChildrenScores(scores, context.viewer.lifestyleProfile, context.candidate.lifestyleProfile);
    _addChildrenScores(scores, context.candidate.lifestyleProfile, context.viewer.lifestyleProfile);
    return scores;
  }

  void _addHabitScores(
    List<double> scores,
    ProfileLifestyle viewer,
    ProfileLifestyle candidate,
  ) {
    _addHabitPair(
      scores,
      habit: candidate.smoking,
      partnerPref: viewer.partnerSmokingPref,
    );
    _addHabitPair(
      scores,
      habit: candidate.drinking,
      partnerPref: viewer.partnerDrinkingPref,
    );
  }

  void _addHabitPair(
    List<double> scores, {
    required String? habit,
    required String? partnerPref,
  }) {
    final level = CompatibilityScoring.habitLevel(habit);
    if (level == null || partnerPref == null || partnerPref.isEmpty) {
      return;
    }
    scores.add(CompatibilityScoring.partnerHabitScore(level, partnerPref));
  }

  void _addChildrenScores(
    List<double> scores,
    ProfileLifestyle viewer,
    ProfileLifestyle candidate,
  ) {
    final direct = CompatibilityScoring.childrenAlignment(
      viewer.childrenPreference,
      candidate.childrenPreference,
    );
    if (viewer.childrenPreference != null &&
        candidate.childrenPreference != null) {
      scores.add(direct);
    }
    final partner = CompatibilityScoring.partnerChildrenScore(
      viewer.partnerChildrenPref,
      candidate.childrenPreference,
    );
    if (partner >= 0) {
      scores.add(partner);
    }
  }
}

class DistanceStrategy implements CompatibilityStrategy {
  const DistanceStrategy({this.weight = 0.14});

  @override
  final double weight;

  @override
  String get id => 'distance';

  @override
  bool applies(CompatibilityContext context) {
    final km = context.distanceKm;
    if (km != null && !km.isNaN) {
      return true;
    }
    final viewerCity = context.viewer.city?.trim();
    final candidateCity = context.candidate.city?.trim();
    return viewerCity != null &&
        viewerCity.isNotEmpty &&
        candidateCity != null &&
        candidateCity.isNotEmpty;
  }

  /// Uses server-derived [CompatibilityContext.distanceKm] only.
  @override
  double score(CompatibilityContext context) {
    final km = context.distanceKm;
    if (km != null && !km.isNaN) {
      final max = context.preferences.maxDistanceKm;
      if (km <= 0) {
        return 1;
      }
      if (km >= max) {
        return 0.15;
      }
      return (1 - (km / max) * 0.7).clamp(0.2, 1);
    }
    final viewerCity = context.viewer.city!.trim().toLowerCase();
    final candidateCity = context.candidate.city!.trim().toLowerCase();
    return viewerCity == candidateCity ? 1 : 0.4;
  }

  @override
  String? reason(CompatibilityContext context) {
    final km = context.distanceKm;
    if (km != null && km <= 5) {
      return 'You are nearby';
    }
    final viewerCity = context.viewer.city?.trim().toLowerCase();
    final candidateCity = context.candidate.city?.trim().toLowerCase();
    if (viewerCity != null &&
        viewerCity.isNotEmpty &&
        viewerCity == candidateCity) {
      return 'You are in the same city';
    }
    return null;
  }
}

class AgeStrategy implements CompatibilityStrategy {
  const AgeStrategy({this.weight = 0.10});

  @override
  final double weight;

  @override
  String get id => 'age';

  @override
  bool applies(CompatibilityContext context) {
    return context.candidate.resolvedAge > 0;
  }

  @override
  double score(CompatibilityContext context) {
    final age = context.candidate.resolvedAge;
    final prefs = context.preferences;
    if (age >= prefs.minAge && age <= prefs.maxAge) {
      return 1;
    }
    final delta = age < prefs.minAge ? prefs.minAge - age : age - prefs.maxAge;
    return (1 - delta / 10).clamp(0, 0.4);
  }

  @override
  String? reason(CompatibilityContext context) => null;
}

class LifestyleStrategy implements CompatibilityStrategy {
  const LifestyleStrategy({this.weight = 0.08});

  @override
  final double weight;

  @override
  String get id => 'lifestyle';

  @override
  bool applies(CompatibilityContext context) {
    return _tags(context.viewer).isNotEmpty && _tags(context.candidate).isNotEmpty;
  }

  @override
  double score(CompatibilityContext context) {
    final viewer = _tags(context.viewer);
    final candidate = _tags(context.candidate);
    return CompatibilityScoring.jaccard(viewer, candidate);
  }

  @override
  String? reason(CompatibilityContext context) => null;

  Set<String> _tags(UserProfile profile) {
    final tags = <String>{};
    tags.addAll(CompatibilityScoring.normalizedSet(profile.lifestyle));
    tags.addAll(CompatibilityScoring.normalizedSet(profile.lifestyleProfile.toTags()));
    return tags;
  }
}

class ActivityStrategy implements CompatibilityStrategy {
  const ActivityStrategy({this.weight = 0.05});

  @override
  final double weight;

  @override
  String get id => 'activity';

  @override
  bool applies(CompatibilityContext context) {
    return context.candidate.lastActiveAt != null ||
        context.candidate.updatedAt != null;
  }

  @override
  double score(CompatibilityContext context) {
    final last = context.candidate.lastActiveAt ?? context.candidate.updatedAt!;
    final hours = DateTime.now().difference(last).inHours;
    if (hours <= 24) {
      return 1;
    }
    if (hours <= 72) {
      return 0.7;
    }
    if (hours <= 24 * 14) {
      return 0.4;
    }
    return 0.15;
  }

  @override
  String? reason(CompatibilityContext context) => null;
}

class CompatibilityEngine {
  CompatibilityEngine(this.strategies)
    : assert(strategies.isNotEmpty, 'At least one strategy is required');

  /// Weighted profile compatibility strategies. Missing data excludes a strategy.
  factory CompatibilityEngine.standard() {
    return CompatibilityEngine(const [
      RelationshipGoalStrategy(),
      InterestStrategy(),
      LanguageStrategy(),
      HobbyStrategy(),
      ValuesStrategy(),
      LifestyleStrategy(),
      DistanceStrategy(),
      AgeStrategy(),
      ActivityStrategy(),
    ]);
  }

  final List<CompatibilityStrategy> strategies;

  CompatibilityResult evaluate(CompatibilityContext context) {
    var activeWeight = 0.0;
    var weighted = 0.0;
    final reasons = <String>[];
    final categoryScores = <String, int>{};
    for (final strategy in strategies) {
      if (!strategy.applies(context)) {
        continue;
      }
      activeWeight += strategy.weight;
      final raw = strategy.score(context);
      weighted += raw * strategy.weight;
      categoryScores[strategy.id] = (raw.clamp(0, 1) * 100).round();
      final reason = strategy.reason(context);
      if (reason != null) {
        reasons.add(reason);
      }
    }
    final normalized = activeWeight == 0 ? 0.0 : weighted / activeWeight;
    final viewerInterests = CompatibilityScoring.normalizedSet(context.viewer.interests);
    final sharedInterests = context.candidate.interests
        .where((item) => viewerInterests.contains(CompatibilityScoring.normalize(item)))
        .toList();
    final viewerLanguages = CompatibilityScoring.normalizedSet(context.viewer.languages);
    final sharedLanguages = context.candidate.languages
        .where((item) => viewerLanguages.contains(CompatibilityScoring.normalize(item)))
        .toList();
    final viewerHobbies = CompatibilityScoring.normalizedSet(context.viewer.hobbies);
    final sharedHobbies = context.candidate.hobbies
        .where((item) => viewerHobbies.contains(CompatibilityScoring.normalize(item)))
        .toList();
    return CompatibilityResult(
      score: (normalized * 100).round().clamp(0, 100),
      sharedInterests: sharedInterests,
      sharedLanguages: sharedLanguages,
      sharedHobbies: sharedHobbies,
      reasons: reasons,
      categoryScores: categoryScores,
    );
  }
}