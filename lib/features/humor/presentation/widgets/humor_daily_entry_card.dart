import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// Days the user chose "Sonra" for, for the rest of this app session. Nothing
/// is sent to the server: the day simply stays pending, and the card returns
/// on the next launch — never as a popup, never as a redirect.
abstract final class HumorDailyDeferral {
  static final Set<String> _days = <String>{};

  static bool isDeferred(String dayId) => _days.contains(dayId);

  static void defer(String dayId) => _days.add(dayId);

  @visibleForTesting
  static void reset() => _days.clear();
}

/// The "Bugünün Mizah Turu 🎭" entry. Shown only for a ready set; a user who
/// finished calibration today sees at most one quiet line, never a CTA.
class HumorDailyEntryCard extends StatelessWidget {
  const HumorDailyEntryCard({
    super.key,
    required this.set,
    this.onStart,
    this.onDefer,
  });

  final HumorDailySet set;

  /// "Başla" / "Devam et". Not offered once the day is complete.
  final VoidCallback? onStart;

  /// "Sonra": hide the card for now without touching server state.
  final VoidCallback? onDefer;

  /// Whether this card renders anything for [set].
  static bool rendersFor(HumorDailySet set) =>
      set.showsEntryCard || set.startsTomorrow;

  /// The CTA text for [set]: "Başla", "Devam et · 4/10" or "Bugünlük tamam ✓".
  static String ctaLabel(AppLocalizations l10n, HumorDailySet set) {
    return switch (HumorDailyCta.of(set)) {
      HumorDailyCta.start => l10n.humorDailyStart,
      HumorDailyCta.resume => l10n.humorDailyResume(
        set.answeredCount,
        set.total,
      ),
      HumorDailyCta.done => l10n.humorDailyDone,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    if (set.startsTomorrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Text(
          l10n.humorDailyStartsTomorrow,
          style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
        ),
      );
    }
    if (!set.showsEntryCard) {
      return const SizedBox.shrink();
    }
    final cta = HumorDailyCta.of(set);
    final onCard = p.onHumorContainer;
    return MevoraCard(
      color: p.humorContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l10n.humorDailyTitle,
                  style: theme.textTheme.titleSmall?.copyWith(color: onCard),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.humorDailyMeta(set.total),
                style: theme.textTheme.labelSmall?.copyWith(color: onCard),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.humorDailyBody,
            style: theme.textTheme.bodySmall?.copyWith(color: onCard),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.humorDailySecondary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: onCard.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          if (cta == HumorDailyCta.done)
            // Quiet and final: nothing here reopens the tour.
            Text(
              ctaLabel(l10n, set),
              style: theme.textTheme.labelLarge?.copyWith(color: onCard),
            )
          else
            Row(
              children: [
                Expanded(
                  child: MevoraButton(
                    label: ctaLabel(l10n, set),
                    size: MevoraButtonSize.small,
                    onPressed: onStart,
                  ),
                ),
                if (onDefer != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  MevoraButton(
                    label: l10n.humorDailyLater,
                    variant: MevoraButtonVariant.ghost,
                    size: MevoraButtonSize.small,
                    isExpanded: false,
                    onPressed: onDefer,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
