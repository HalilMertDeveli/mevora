import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Deterministic "Why you match" reasons from real profile + breakdown data.
abstract final class CompatibilityReasonEngine {
  static List<CompatibilityReason> build({
    required UserProfile viewer,
    required UserProfile candidate,
    required CompatibilityBreakdown breakdown,
  }) {
    final reasons = <CompatibilityReason>[];

    if (breakdown.relationshipScore >= 85 &&
        viewer.relationshipGoal != null &&
        viewer.relationshipGoal == candidate.relationshipGoal) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonSameRelationshipGoal',
          messageArgs: [_goalLabel(viewer.relationshipGoal!)],
          category: CompatibilityCategory.relationship,
          priority: CompatibilityReasonPriority.high,
          iconName: 'favorite',
        ),
      );
    }

    if (breakdown.sharedInterests.isNotEmpty) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonSharedInterests',
          messageArgs: breakdown.sharedInterests.take(3).toList(),
          category: CompatibilityCategory.interests,
          priority: CompatibilityReasonPriority.high,
          iconName: 'interests',
        ),
      );
    }

    if (breakdown.lifestyleScore >= 70) {
      reasons.add(
        const CompatibilityReason(
          messageKey: 'compatReasonSimilarLifestyle',
          category: CompatibilityCategory.lifestyle,
          priority: CompatibilityReasonPriority.medium,
          iconName: 'lifestyle',
        ),
      );
    }

    if (breakdown.hasQuestionData &&
        breakdown.questionAlignedCount != null &&
        breakdown.questionSharedCount != null &&
        breakdown.questionAlignedCount! > 0) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonSameAnswers',
          messageArgs: [
            '${breakdown.questionAlignedCount}',
            '${breakdown.questionSharedCount}',
          ],
          category: CompatibilityCategory.questions,
          priority: CompatibilityReasonPriority.high,
          iconName: 'psychology',
        ),
      );
    }

    if (breakdown.hasMusicData && breakdown.musicScore! >= 70) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonSimilarMusic',
          messageArgs: ['${breakdown.musicScore}'],
          category: CompatibilityCategory.music,
          priority: CompatibilityReasonPriority.medium,
          iconName: 'music_note',
        ),
      );
    }

    if (breakdown.communicationScore != null &&
        breakdown.communicationScore! >= 75) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonCommunication',
          category: CompatibilityCategory.communication,
          priority: CompatibilityReasonPriority.medium,
          iconName: 'forum',
        ),
      );
    }

    reasons.sort((a, b) {
      const order = {
        CompatibilityReasonPriority.high: 0,
        CompatibilityReasonPriority.medium: 1,
        CompatibilityReasonPriority.low: 2,
      };
      return order[a.priority]!.compareTo(order[b.priority]!);
    });

    return reasons.take(6).toList();
  }

  static String _goalLabel(String goal) {
    switch (goal) {
      case 'longTerm':
        return 'longTerm';
      case 'casual':
        return 'casual';
      case 'figuringOut':
        return 'figuringOut';
      default:
        return goal;
    }
  }

  static String categoryLabelKey(CompatibilityCategory category) {
    return switch (category) {
      CompatibilityCategory.overall => 'compatCategoryOverall',
      CompatibilityCategory.relationship => 'compatCategoryRelationship',
      CompatibilityCategory.interests => 'compatCategoryInterests',
      CompatibilityCategory.lifestyle => 'compatCategoryLifestyle',
      CompatibilityCategory.questions => 'compatCategoryQuestions',
      CompatibilityCategory.music => 'compatCategoryMusic',
      CompatibilityCategory.communication => 'compatCategoryCommunication',
      CompatibilityCategory.proximity => 'compatCategoryProximity',
      CompatibilityCategory.activity => 'compatCategoryActivity',
    };
  }
}
