import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Resolves deterministic compatibility reason keys to localized copy.
abstract final class CompatibilityL10n {
  static String reason(AppLocalizations l10n, CompatibilityReason reason) {
    switch (reason.messageKey) {
      case 'compatReasonSameRelationshipGoal':
        return l10n.compatReasonSameRelationshipGoal(
          _goalLabel(l10n, reason.messageArgs.first),
        );
      case 'compatReasonSharedInterests':
        return l10n.compatReasonSharedInterests(
          reason.messageArgs.join(', '),
        );
      case 'compatReasonSimilarLifestyle':
        return l10n.compatReasonSimilarLifestyle;
      case 'compatReasonSameAnswers':
        return l10n.compatReasonSameAnswers(
          reason.messageArgs.elementAt(0),
          reason.messageArgs.elementAt(1),
        );
      case 'compatReasonSimilarMusic':
        return l10n.compatReasonSimilarMusic(reason.messageArgs.first);
      case 'compatReasonCommunication':
        return l10n.compatReasonCommunication;
      default:
        return reason.messageKey;
    }
  }

  static String category(AppLocalizations l10n, CompatibilityCategory category) {
    return switch (category) {
      CompatibilityCategory.overall => l10n.compatCategoryOverall,
      CompatibilityCategory.relationship => l10n.compatCategoryRelationship,
      CompatibilityCategory.interests => l10n.compatCategoryInterests,
      CompatibilityCategory.lifestyle => l10n.compatCategoryLifestyle,
      CompatibilityCategory.questions => l10n.compatCategoryQuestions,
      CompatibilityCategory.music => l10n.compatCategoryMusic,
      CompatibilityCategory.communication => l10n.compatCategoryCommunication,
      CompatibilityCategory.proximity => l10n.compatCategoryProximity,
      CompatibilityCategory.activity => l10n.compatCategoryActivity,
    };
  }

  static String _goalLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'longTerm' => l10n.relationshipGoalLongTerm,
      'casual' => l10n.relationshipGoalCasual,
      'figuringOut' => l10n.relationshipGoalFiguringOut,
      _ => key,
    };
  }
}
