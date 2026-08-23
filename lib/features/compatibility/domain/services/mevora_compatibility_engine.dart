import 'package:mevora/features/compatibility/domain/config/compatibility_weights.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/entities/hidden_compatibility_insight.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_breakdown_mapper.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

/// Central Mevora compatibility calculator — composes profile engine + question/music signals.
abstract final class MevoraCompatibilityEngine {
  static CompatibilityBreakdown calculate({
    required UserProfile viewer,
    required UserProfile candidate,
    DiscoveryPreferences preferences = const DiscoveryPreferences(),
    double? distanceKm,
    int? relationshipCompatibilityScore,
    int? relationshipAlignedCount,
    int? relationshipSharedCount,
    List<String> relationshipSummaryTopics = const [],
    int? musicCompatibilityScore,
  }) {
    final context = CompatibilityContext(
      viewer: viewer,
      candidate: candidate,
      preferences: preferences,
      distanceKm: distanceKm,
    );
    final engine = CompatibilityEngine.standard();
    final profileResult = engine.evaluate(context);
    final categoryScores = _profileCategoryScores(engine, context);

    final questionScore = relationshipCompatibilityScore;
    final musicScore = musicCompatibilityScore;
    final communicationScore = _communicationScore(
      relationshipSummaryTopics,
      relationshipAlignedCount,
      relationshipSharedCount,
    );

    final weightedParts = <({double weight, int? score})>[
      (weight: CompatibilityWeights.profile, score: profileResult.score),
      if (questionScore != null && relationshipSharedCount != null && relationshipSharedCount > 0)
        (weight: CompatibilityWeights.questions, score: questionScore),
      if (musicScore != null) (weight: CompatibilityWeights.music, score: musicScore),
    ];

    final activeWeight = weightedParts.fold<double>(
      0,
      (sum, part) => sum + (part.score == null ? 0 : part.weight),
    );
    var overall = 0;
    CompatibilityDataQuality quality;
    if (activeWeight <= 0) {
      overall = 0;
      quality = CompatibilityDataQuality.insufficient;
    } else {
      final weightedSum = weightedParts.fold<double>(0, (sum, part) {
        if (part.score == null) {
          return sum;
        }
        return sum + part.score! * part.weight;
      });
      overall = (weightedSum / activeWeight).round().clamp(0, 100);
      quality = _quality(
        profileResult: profileResult.score,
        questionShared: relationshipSharedCount,
        musicScore: musicScore,
      );
    }

    final categories = <CompatibilityCategory, int>{
      CompatibilityCategory.relationship: categoryScores.relationship,
      CompatibilityCategory.interests: categoryScores.interests,
      CompatibilityCategory.lifestyle: categoryScores.lifestyle,
      CompatibilityCategory.proximity: categoryScores.proximity,
      CompatibilityCategory.activity: categoryScores.activity,
      if (questionScore != null)
        CompatibilityCategory.questions: questionScore,
      if (musicScore != null) CompatibilityCategory.music: musicScore,
      if (communicationScore != null)
        CompatibilityCategory.communication: communicationScore,
    };

    final strongest = _extremeCategory(categories, highest: true);
    final weakest = _extremeCategory(categories, highest: false);

    return CompatibilityBreakdown(
      overallScore: overall,
      relationshipScore: categoryScores.relationship,
      interestScore: categoryScores.interests,
      lifestyleScore: categoryScores.lifestyle,
      questionScore: questionScore,
      musicScore: musicScore,
      communicationScore: communicationScore,
      proximityScore: categoryScores.proximity,
      activityScore: categoryScores.activity,
      dataQuality: quality,
      sharedInterests: profileResult.sharedInterests,
      questionAlignedCount: relationshipAlignedCount,
      questionSharedCount: relationshipSharedCount,
      strongestCategory: strongest,
      weakestCategory: weakest,
    );
  }

  /// Build breakdown from a discovery card (server-authoritative fields).
  static CompatibilityBreakdown fromCandidate({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
    DiscoveryPreferences preferences = const DiscoveryPreferences(),
  }) {
    final hasServerCategories = candidate.categoryRelationshipScore != null ||
        candidate.categoryInterestScore != null;
    if (candidate.hasCompatibilityScore || hasServerCategories) {
      final mapped = CompatibilityBreakdownMapper.fromCandidate(candidate);
      final overall = candidate.hasCompatibilityScore
          ? candidate.compatibilityScore
          : _overallFromCategories(candidate);
      if (overall > 0) {
        return mapped.copyWith(
          overallScore: overall,
          dataQuality: CompatibilityDataQuality.sufficient,
        );
      }
    }

    return calculate(
      viewer: viewer,
      candidate: UserProfile(
        uid: candidate.uid,
        displayName: candidate.displayName,
        age: candidate.age,
        interests: candidate.interests,
        relationshipGoal: candidate.relationshipGoal,
        city: candidate.city,
      ),
      preferences: preferences,
      distanceKm: candidate.distanceKm,
      relationshipCompatibilityScore: candidate.relationshipCompatibilityScore,
      relationshipAlignedCount: candidate.relationshipAlignedCount,
      relationshipSharedCount: candidate.relationshipSharedViewCount,
      relationshipSummaryTopics: candidate.relationshipSummaryTopics,
      musicCompatibilityScore: candidate.musicCompatibilityScore,
    );
  }

  static int _overallFromCategories(DiscoveryCandidate candidate) {
    final parts = <double>[];
    var weightSum = 0.0;
    void add(int? value, double weight) {
      if (value != null && value > 0) {
        parts.add(value * weight);
        weightSum += weight;
      }
    }

    add(candidate.categoryInterestScore, 0.35);
    add(candidate.categoryRelationshipScore, 0.25);
    add(candidate.categoryLifestyleScore, 0.2);
    add(candidate.categoryQuestionScore, 0.15);
    add(candidate.categoryMusicScore, 0.15);
    if (weightSum <= 0) {
      return 0;
    }
    return (parts.fold<double>(0, (a, b) => a + b) / weightSum)
        .round()
        .clamp(1, 100);
  }

  static HiddenCompatibilityInsight? hiddenInsight(
    List<DiscoveryCandidate> candidates, {
    Set<String> excludeUids = const {},
  }) {
    HiddenCompatibilityInsight? best;
    for (final candidate in candidates) {
      if (excludeUids.contains(candidate.uid)) {
        continue;
      }
      final aligned = candidate.relationshipAlignedCount;
      final shared = candidate.relationshipSharedViewCount;
      final qScore = candidate.relationshipCompatibilityScore;
      if (aligned == null ||
          shared == null ||
          qScore == null ||
          shared <= 0) {
        continue;
      }
      if (aligned < CompatibilityWeights.hiddenCompatibilityMinAligned) {
        continue;
      }
      if (qScore < CompatibilityWeights.hiddenCompatibilityMinScore) {
        continue;
      }
      if (!candidate.hasCompatibilityScore ||
          candidate.compatibilityScore <
              CompatibilityWeights.hiddenCompatibilityMinOverall) {
        continue;
      }
      final insight = HiddenCompatibilityInsight(
        candidateUid: candidate.uid,
        overallScore: candidate.compatibilityScore,
        questionScore: qScore,
        alignedCount: aligned,
        sharedQuestionCount: shared,
      );
      if (best == null || insight.questionScore > best.questionScore) {
        best = insight;
      }
    }
    return best;
  }

  static CompatibilityDataQuality _quality({
    required int profileResult,
    required int? questionShared,
    required int? musicScore,
  }) {
    final hasProfile = profileResult > 0;
    final hasQuestions = (questionShared ?? 0) > 0;
    final hasMusic = musicScore != null;
    if (hasProfile && (hasQuestions || hasMusic)) {
      return CompatibilityDataQuality.sufficient;
    }
    if (hasProfile || hasQuestions || hasMusic) {
      return CompatibilityDataQuality.partial;
    }
    return CompatibilityDataQuality.insufficient;
  }

  static _CategoryScores _profileCategoryScores(
    CompatibilityEngine engine,
    CompatibilityContext context,
  ) {
    int toPercent(double raw) => (raw.clamp(0, 1) * 100).round();
    final strategies = engine.strategies;
    double scoreFor(String id) {
      for (final strategy in strategies) {
        if (strategy.id == id) {
          return strategy.score(context);
        }
      }
      return 0.5;
    }

    return _CategoryScores(
      relationship: toPercent(scoreFor('relationshipGoal')),
      interests: toPercent(scoreFor('interests')),
      lifestyle: toPercent(scoreFor('lifestyle')),
      proximity: toPercent(scoreFor('distance')),
      activity: toPercent(scoreFor('activity')),
    );
  }

  static int? _communicationScore(
    List<String> topics,
    int? aligned,
    int? shared,
  ) {
    if (aligned == null || shared == null || shared <= 0) {
      return null;
    }
    if (!topics.contains(RelationshipTopic.communication.name)) {
      return null;
    }
    return ((aligned / shared) * 100).round().clamp(0, 100);
  }

  static CompatibilityCategory? _extremeCategory(
    Map<CompatibilityCategory, int> scores, {
    required bool highest,
  }) {
    if (scores.isEmpty) {
      return null;
    }
    final entries = scores.entries.toList();
    entries.sort((a, b) => highest
        ? b.value.compareTo(a.value)
        : a.value.compareTo(b.value));
    return entries.first.key;
  }
}

class _CategoryScores {
  const _CategoryScores({
    required this.relationship,
    required this.interests,
    required this.lifestyle,
    required this.proximity,
    required this.activity,
  });

  final int relationship;
  final int interests;
  final int lifestyle;
  final int proximity;
  final int activity;
}
