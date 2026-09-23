import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Presentation helpers for humor profile sheets (no hardcoded English).
abstract final class HumorProfileDisplay {
  static String categoryLabel(AppLocalizations l10n, HumorCategory category) {
    return switch (category) {
      HumorCategory.sarcasm => l10n.humorCategorySarcasm,
      HumorCategory.absurd => l10n.humorCategoryAbsurd,
      HumorCategory.silly => l10n.humorCategorySilly,
      HumorCategory.romantic => l10n.humorCategoryRomantic,
      HumorCategory.dark => l10n.humorCategoryDark,
      HumorCategory.meme => l10n.humorCategoryMeme,
      HumorCategory.dry => l10n.humorCategoryDry,
      HumorCategory.wordplay => l10n.humorCategoryWordplay,
      HumorCategory.situational => l10n.humorCategorySituational,
      HumorCategory.cringe => l10n.humorCategoryCringe,
      HumorCategory.teasing => l10n.humorCategoryTeasing,
    };
  }

  static String buildingLabel(AppLocalizations l10n, UserHumorProfile profile) {
    if (!profile.profileBuilding) {
      return l10n.humorProfileTitle;
    }
    return l10n.humorProfileBuilding;
  }

  static int remainingToReady(UserHumorProfile profile) {
    final left = HumorFeedPolicy.buildingThreshold - profile.interactionCount;
    return left < 0 ? 0 : left;
  }

  /// Strength bucket for a 0–100 dimension.
  ///
  /// The underlying vector stays precise; the user sees a bucket. Showing
  /// "Sarcasm 83.7%" would claim a precision this measurement does not have —
  /// fifteen ratings cannot resolve a dimension to a decimal point.
  static HumorStrength strengthOf(num value) {
    if (value >= 75) {
      return HumorStrength.high;
    }
    if (value >= 60) {
      return HumorStrength.medium;
    }
    return HumorStrength.low;
  }

  static String strengthLabel(AppLocalizations l10n, HumorStrength strength) {
    return switch (strength) {
      HumorStrength.high => l10n.humorResultStrengthHigh,
      HumorStrength.medium => l10n.humorResultStrengthMedium,
      HumorStrength.low => l10n.humorResultStrengthLow,
    };
  }

  /// The dimension the profile leans *away* from, if it leans at all.
  ///
  /// Only returned when the signal is real: a dimension sitting near the
  /// neutral midpoint means "no evidence", not "dislikes", and saying
  /// otherwise would be inventing a trait.
  static HumorCategory? weakestVibe(UserHumorProfile profile) {
    if (profile.vector.isEmpty) {
      return null;
    }
    final entries = profile.vector.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final lowest = entries.first;
    return lowest.value <= 35 ? lowest.key : null;
  }

  /// Deterministic, template-based description of the profile.
  ///
  /// No model call at runtime: the same profile always produces the same
  /// sentence, which is testable and cannot drift or hallucinate. It stays
  /// modest on purpose — it describes what landed, not who the person is.
  static String summarySentence(
    AppLocalizations l10n,
    UserHumorProfile profile,
  ) {
    final top = visibleTopVibes(
      profile,
      max: 2,
    ).where((vibe) => vibe.value >= 60).toList();
    final buffer = StringBuffer();
    if (top.isEmpty) {
      buffer.write(l10n.humorResultSummaryNone);
    } else if (top.length == 1) {
      buffer.write(
        l10n.humorResultSummaryOne(categoryLabel(l10n, top.first.category)),
      );
    } else {
      buffer.write(
        l10n.humorResultSummaryTwo(
          categoryLabel(l10n, top[0].category),
          categoryLabel(l10n, top[1].category),
        ),
      );
    }
    final weakest = weakestVibe(profile);
    if (top.isNotEmpty && weakest != null) {
      buffer.write(' ');
      buffer.write(l10n.humorResultContrast(categoryLabel(l10n, weakest)));
    }
    return buffer.toString();
  }

  static List<HumorVibe> visibleTopVibes(
    UserHumorProfile profile, {
    int max = 3,
  }) {
    if (profile.topVibes.isNotEmpty) {
      return profile.topVibes.take(max).toList();
    }
    final entries = profile.vector.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(max)
        .map((e) => HumorVibe(category: e.key, value: e.value.round()))
        .toList();
  }
}

/// How strongly a humor dimension registers, as shown to the user.
///
/// Three buckets rather than a number: the profile is built from a small
/// number of ratings, and a percentage would overstate what it knows.
enum HumorStrength { low, medium, high }
