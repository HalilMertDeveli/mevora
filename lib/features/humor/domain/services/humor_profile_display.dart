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
