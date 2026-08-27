import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reveal.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Client-side fallback that mirrors server reveal rules (verified data only).
abstract final class CompatibilityRevealBuilder {
  static const freeLimit = 2;
  static const premiumLimit = 3;

  static CompatibilityReveal build({
    required UserProfile viewer,
    required UserProfile candidate,
    required CompatibilityBreakdown breakdown,
    required bool isPremium,
    List<String> questionTopTopics = const [],
  }) {
    final points = <CompatibilityRevealPoint>[];

    final hasQuestions =
        breakdown.hasQuestionData &&
        (breakdown.questionAlignedCount ?? 0) > 0;

    final personalityTopic = questionTopTopics.any(
      (t) =>
          t == 'personality' ||
          t == 'values' ||
          t == 'life_values' ||
          t == 'trust' ||
          t == 'boundaries' ||
          t == 'personalSpace' ||
          t == 'expectations' ||
          t == 'loyalty' ||
          t == 'friendship',
    );

    if (hasQuestions && personalityTopic) {
      points.add(
        CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.personality,
          messageKey: 'compatRevealPersonalityAligned',
          messageArgs: ['${breakdown.questionAlignedCount}'],
          score: breakdown.questionScore,
        ),
      );
    } else if (breakdown.lifestyleScore >= 70) {
      points.add(
        CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.personality,
          messageKey: 'compatRevealSimilarPersonality',
          score: breakdown.lifestyleScore,
        ),
      );
    }

    if (hasQuestions) {
      points.add(
        CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.questions,
          messageKey: 'compatReasonSameAnswers',
          messageArgs: [
            '${breakdown.questionAlignedCount}',
            '${breakdown.questionSharedCount}',
          ],
          score: breakdown.questionScore,
        ),
      );
    }

    if (breakdown.hasMusicData && breakdown.musicScore! > 0) {
      points.add(
        CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.music,
          messageKey: 'compatReasonSimilarMusic',
          messageArgs: ['${breakdown.musicScore}'],
          score: breakdown.musicScore,
        ),
      );
    }

    final viewerGoal = viewer.relationshipGoal?.trim();
    final candidateGoal = candidate.relationshipGoal?.trim();
    if (viewerGoal != null &&
        candidateGoal != null &&
        viewerGoal.isNotEmpty &&
        viewerGoal.toLowerCase() == candidateGoal.toLowerCase() &&
        breakdown.relationshipScore >= 85) {
      points.add(
        CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.relationship,
          messageKey: 'compatReasonSameRelationshipGoal',
          messageArgs: [_goalLabel(viewerGoal)],
          score: breakdown.relationshipScore,
        ),
      );
    }

    if (breakdown.sharedInterests.isNotEmpty) {
      points.add(
        CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.preference,
          messageKey: 'compatReasonSharedInterests',
          messageArgs: breakdown.sharedInterests.take(3).toList(),
          score: breakdown.interestScore,
        ),
      );
    }

    if (breakdown.communicationScore != null &&
        breakdown.communicationScore! >= 75 &&
        questionTopTopics.contains('communication')) {
      points.add(
        const CompatibilityRevealPoint(
          kind: CompatibilityRevealKind.lifestyle,
          messageKey: 'compatReasonCommunication',
        ),
      );
    }

    if (points.isEmpty || breakdown.overallScore <= 0) {
      return CompatibilityReveal(
        available: false,
        overallScore: breakdown.overallScore,
        isPremium: isPremium,
        premiumRequired: !isPremium,
        reason: 'insufficient_data',
      );
    }

    final limit = isPremium ? premiumLimit : freeLimit;
    return CompatibilityReveal(
      available: true,
      overallScore: breakdown.overallScore,
      isPremium: isPremium,
      premiumRequired: !isPremium,
      points: points.take(limit).toList(),
      breakdown: isPremium
          ? CompatibilityRevealBreakdown(
              relationshipScore: breakdown.relationshipScore,
              interestScore: breakdown.interestScore,
              lifestyleScore: breakdown.lifestyleScore,
              questionScore: breakdown.questionScore,
              musicScore: breakdown.musicScore,
              communicationScore: breakdown.communicationScore,
            )
          : null,
    );
  }

  static String _goalLabel(String goal) {
    final normalized = goal.replaceAll('_', '').toLowerCase();
    if (normalized == 'longterm') {
      return 'longTerm';
    }
    if (normalized == 'figuringout') {
      return 'figuringOut';
    }
    return goal;
  }
}
