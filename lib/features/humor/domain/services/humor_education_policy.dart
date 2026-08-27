import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Soft education milestones — sparse, never every rating.
abstract final class HumorEducationPolicy {
  /// Soft "profile shaping" sheet after enough ratings.
  static const int shapingMilestone = 12;

  /// Celebrate richer profile once enough interactions exist.
  static const int profileMilestone = 20;

  /// Hide inline rating help after this many interactions.
  static const int ratingHelpAutoHideAfter = 5;

  /// Hint snackbars at these exact interaction counts (once each).
  static const List<int> hintMilestones = [1, 5, 10, 15];

  static bool shouldShowRatingHelp({
    required int interactionCount,
    required bool dismissed,
  }) {
    if (dismissed) return false;
    return interactionCount < ratingHelpAutoHideAfter;
  }

  static bool isHintMilestone(int interactionCount) {
    return hintMilestones.contains(interactionCount);
  }

  static bool isShapingMilestone(int interactionCount) {
    return interactionCount == shapingMilestone;
  }

  static bool isProfileMilestone(int interactionCount) {
    return interactionCount == profileMilestone;
  }

  static String? hintMessage(AppLocalizations l10n, int interactionCount) {
    return switch (interactionCount) {
      1 => l10n.humorHintFirstRating,
      5 => l10n.humorHintFiveRatings,
      10 => l10n.humorHintTenRatings,
      15 => l10n.humorHintFifteenRatings,
      _ => null,
    };
  }

  static double learningProgress(int interactionCount) {
    return (interactionCount / HumorFeedPolicy.buildingThreshold).clamp(0.0, 1.0);
  }
}
