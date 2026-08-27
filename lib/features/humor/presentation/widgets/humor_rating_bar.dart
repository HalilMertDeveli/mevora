import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Always-visible 5-level humor rating bar.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.humorHowFunny,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final rating in _order)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _RatingChip(
                      label: _label(l10n, rating),
                      icon: _icon(rating),
                      selected: selected == rating,
                      enabled: enabled,
                      onTap: () => onRated(rating),
                      color: theme.colorScheme,
                    ),
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
      HumorRating.veryFunny => Icons.sentiment_very_satisfied_rounded,
      HumorRating.funny => Icons.sentiment_satisfied_alt_rounded,
      HumorRating.neutral => Icons.sentiment_neutral_rounded,
      HumorRating.notFunny => Icons.sentiment_dissatisfied_rounded,
      HumorRating.notAtAll => Icons.sentiment_very_dissatisfied_rounded,
    };
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color.primary : color.surfaceContainerHighest;
    final fg = selected ? color.onPrimary : color.onSurfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
