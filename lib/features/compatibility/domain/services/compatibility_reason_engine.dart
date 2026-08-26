import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
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
        CompatibilityScoring.normalizeRelationshipGoal(viewer.relationshipGoal) ==
            CompatibilityScoring.normalizeRelationshipGoal(
              candidate.relationshipGoal,
            ) &&
        viewer.relationshipGoal != null) {
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

    final sharedLanguages = _sharedLanguages(viewer, candidate);
    if (sharedLanguages.isNotEmpty && (breakdown.languageScore ?? 0) >= 50) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonSharedLanguages',
          messageArgs: [sharedLanguages.take(3).join(', ')],
          category: CompatibilityCategory.languages,
          priority: CompatibilityReasonPriority.high,
          iconName: 'translate',
        ),
      );
    }

    final sharedHobbies = _sharedHobbies(viewer, candidate);
    if (sharedHobbies.isNotEmpty && (breakdown.hobbyScore ?? 0) >= 50) {
      reasons.add(
        CompatibilityReason(
          messageKey: 'compatReasonSharedHobbies',
          messageArgs: [sharedHobbies.take(3).join(', ')],
          category: CompatibilityCategory.hobbies,
          priority: CompatibilityReasonPriority.medium,
          iconName: 'hobbies',
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
        const CompatibilityReason(
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
    final normalized = goal.replaceAll('_', '').toLowerCase();
    if (normalized == 'longterm') {
      return 'longTerm';
    }
    return goal;
  }

  static List<String> _sharedLanguages(UserProfile a, UserProfile b) {
    final viewer = a.languages.map((e) => e.trim().toLowerCase()).toSet();
    return b.languages
        .where((lang) => viewer.contains(lang.trim().toLowerCase()))
        .toList();
  }

  static List<String> _sharedHobbies(UserProfile a, UserProfile b) {
    final viewer = a.hobbies.map((e) => e.trim().toLowerCase()).toSet();
    return b.hobbies
        .where((hobby) => viewer.contains(hobby.trim().toLowerCase()))
        .toList();
  }

  static String categoryLabelKey(CompatibilityCategory category) {
    return switch (category) {
      CompatibilityCategory.overall => 'compatCategoryOverall',
      CompatibilityCategory.relationship => 'compatCategoryRelationship',
      CompatibilityCategory.interests => 'compatCategoryInterests',
      CompatibilityCategory.languages => 'compatCategoryLanguages',
      CompatibilityCategory.hobbies => 'compatCategoryHobbies',
      CompatibilityCategory.lifestyle => 'compatCategoryLifestyle',
      CompatibilityCategory.lifeValues => 'compatCategoryValues',
      CompatibilityCategory.questions => 'compatCategoryQuestions',
      CompatibilityCategory.music => 'compatCategoryMusic',
      CompatibilityCategory.communication => 'compatCategoryCommunication',
      CompatibilityCategory.proximity => 'compatCategoryProximity',
      CompatibilityCategory.activity => 'compatCategoryActivity',
    };
  }
}
