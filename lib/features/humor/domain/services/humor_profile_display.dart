import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Presentation helpers for humor profile sheets (no hardcoded English).
abstract final class HumorProfileDisplay {
  static String categoryLabel(AppLocalizations l10n, HumorCategory category) {
    // Category names are product taxonomy; keep stable English tokens for MVP
    // until dedicated per-category l10n keys exist. Surfaces still wrap with
    // localized section titles (humorTopVibes / humorProfileTitle).
    return category.apiValue;
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
