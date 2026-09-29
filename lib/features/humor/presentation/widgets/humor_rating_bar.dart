import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// Always-visible 5-level humor scale: five faces, one tap.
///
/// Light enough not to compete with the clip above it — outlined discs at
/// rest, a single marigold disc for the chosen answer. Labels wrap to two
/// lines instead of shrinking, so "Hiç komik değil" stays readable.
class HumorRatingBar extends StatelessWidget {
  const HumorRatingBar({
    super.key,
    required this.onRated,
    this.selected,
    this.enabled = true,
  });

  final ValueChanged<HumorRating> onRated;
  final HumorRating? selected;
  final bool enabled;

  static const _order = HumorRating.values;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Semantics(
      label: l10n.humorHowFunny,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.humorHowFunny,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final rating in _order)
                Expanded(
                  child: _RatingFace(
                    label: _label(l10n, rating),
                    icon: _icon(rating),
                    selected: selected == rating,
                    enabled: enabled,
                    onTap: () => onRated(rating),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _label(AppLocalizations l10n, HumorRating rating) {
    return switch (rating) {
      HumorRating.veryFunny => l10n.humorRatingVeryFunny,
      HumorRating.funny => l10n.humorRatingFunny,
      HumorRating.neutral => l10n.humorRatingNeutral,
      HumorRating.notFunny => l10n.humorRatingNotFunny,
      HumorRating.notAtAll => l10n.humorRatingNotAtAll,
    };
  }

  static IconData _icon(HumorRating rating) {
    return switch (rating) {
      HumorRating.veryFunny => MevoraIcons.ratingVeryFunny,
      HumorRating.funny => MevoraIcons.ratingFunny,
      HumorRating.neutral => MevoraIcons.ratingNeutral,
      HumorRating.notFunny => MevoraIcons.ratingMeh,
      HumorRating.notAtAll => MevoraIcons.ratingNotFunny,
    };
  }
}

class _RatingFace extends StatelessWidget {
  const _RatingFace({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: MevoraPressScale(
        enabled: enabled,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppDurations.fast,
                  curve: AppCurves.standard,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? p.humor : p.surface,
                    border: Border.all(
                      color: selected ? p.humor : p.border,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: selected ? AppColors.paper : p.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0,
                    color: selected ? p.onHumorContainer : p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
