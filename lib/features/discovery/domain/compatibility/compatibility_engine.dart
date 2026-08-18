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
  });

  /// 0–100 inclusive.
  final int score;
  final List<String> sharedInterests;
  final List<String> reasons;
}

/// Weighted scoring strategy. Add an AI strategy later without changing callers.
abstract class CompatibilityStrategy {
  String get id;

  double get weight;

  /// Raw score in 0–1.
  double score(CompatibilityContext context);

  String? reason(CompatibilityContext context);
}

class InterestStrategy implements CompatibilityStrategy {
  const InterestStrategy({this.weight = 0.25});

  @override
  final double weight;

  @override
  String get id => 'interests';

  @override
  double score(CompatibilityContext context) {
    if (context.viewer.interests.isEmpty ||
        context.candidate.interests.isEmpty) {
      return 0.5;
    }
    final viewer = context.viewer.interests.map(_norm).toSet();
    final candidate = context.candidate.interests.map(_norm).toSet();
    final shared = viewer.intersection(candidate);
    final union = viewer.union(candidate);
    if (union.isEmpty) {
      return 0.5;
    }
    return (shared.length / union.length).clamp(0, 1);
  }

  @override
  String? reason(CompatibilityContext context) {
    final viewer = context.viewer.interests.map(_norm).toSet();
    final shared = context.candidate.interests
        .where((interest) => viewer.contains(_norm(interest)))
        .toList();
    if (shared.isEmpty) {
      return null;
    }
    return 'You both like ${shared.take(3).join(', ')}';
  }

  String _norm(String value) => value.trim().toLowerCase();
}

class RelationshipGoalStrategy implements CompatibilityStrategy {
  const RelationshipGoalStrategy({this.weight = 0.20});

  @override
  final double weight;

  @override
  String get id => 'relationshipGoal';

  @override
  double score(CompatibilityContext context) {
    final viewer = context.viewer.relationshipGoal?.trim().toLowerCase();
    final candidate = context.candidate.relationshipGoal?.trim().toLowerCase();
    if (viewer == null || candidate == null) {
      return 0.5;
    }
    return viewer == candidate ? 1 : 0.35;
  }

  @override
  String? reason(CompatibilityContext context) {
    final viewer = context.viewer.relationshipGoal?.trim().toLowerCase();
    final candidate = context.candidate.relationshipGoal?.trim().toLowerCase();
    if (viewer != null && viewer == candidate) {
      return 'You want the same kind of relationship';
    }
    return null;
  }
}

class DistanceStrategy implements CompatibilityStrategy {
  const DistanceStrategy({this.weight = 0.20});

  @override
  final double weight;

  @override
  String get id => 'distance';

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
    final viewerCity = context.viewer.city?.trim().toLowerCase();
    final candidateCity = context.candidate.city?.trim().toLowerCase();
    if (viewerCity == null ||
        viewerCity.isEmpty ||
        candidateCity == null ||
        candidateCity.isEmpty) {
      return 0.5;
    }
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
  const AgeStrategy({this.weight = 0.15});

  @override
  final double weight;

  @override
  String get id => 'age';

  @override
  double score(CompatibilityContext context) {
    final age = context.candidate.resolvedAge;
    if (age <= 0) {
      return 0.5;
    }
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
  const LifestyleStrategy({this.weight = 0.10});

  @override
  final double weight;

  @override
  String get id => 'lifestyle';

  @override
  double score(CompatibilityContext context) {
    if (context.viewer.lifestyle.isEmpty ||
        context.candidate.lifestyle.isEmpty) {
      return 0.5;
    }
    final viewer = context.viewer.lifestyle.map(_norm).toSet();
    final shared = context.candidate.lifestyle
        .where((item) => viewer.contains(_norm(item)))
        .length;
    return (shared / viewer.length).clamp(0, 1);
  }

  @override
  String? reason(CompatibilityContext context) => null;

  String _norm(String value) => value.trim().toLowerCase();
}

class ActivityStrategy implements CompatibilityStrategy {
  const ActivityStrategy({this.weight = 0.10});

  @override
  final double weight;

  @override
  String get id => 'activity';

  @override
  double score(CompatibilityContext context) {
    final last = context.candidate.lastActiveAt ?? context.candidate.updatedAt;
    if (last == null) {
      return 0.4;
    }
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

  /// Spec weights: interests 25%, goal 20%, distance 20%, age 15%,
  /// lifestyle 10%, activity 10%.
  factory CompatibilityEngine.standard() {
    return CompatibilityEngine(const [
      InterestStrategy(),
      RelationshipGoalStrategy(),
      DistanceStrategy(),
      AgeStrategy(),
      LifestyleStrategy(),
      ActivityStrategy(),
    ]);
  }

  final List<CompatibilityStrategy> strategies;

  CompatibilityResult evaluate(CompatibilityContext context) {
    final totalWeight = strategies.fold<double>(
      0,
      (sum, strategy) => sum + strategy.weight,
    );
    var weighted = 0.0;
    final reasons = <String>[];
    for (final strategy in strategies) {
      weighted += strategy.score(context) * strategy.weight;
      final reason = strategy.reason(context);
      if (reason != null) {
        reasons.add(reason);
      }
    }
    final normalized = totalWeight == 0 ? 0.0 : weighted / totalWeight;
    final shared = context.viewer.interests
        .map((item) => item.trim().toLowerCase())
        .toSet()
        .intersection(
          context.candidate.interests
              .map((item) => item.trim().toLowerCase())
              .toSet(),
        )
        .toList();
    return CompatibilityResult(
      score: (normalized * 100).round().clamp(0, 100),
      sharedInterests: shared,
      reasons: reasons,
    );
  }
}
