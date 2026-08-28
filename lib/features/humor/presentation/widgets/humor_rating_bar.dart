import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Binary Humor Lab rating: Funny / Not funny — one tap advances the feed.
class HumorRatingBar extends StatelessWidget {
  const HumorRatingBar({
    super.key,
    required this.onRated,
    this.selected,
    this.enabled = true,
    this.subtitle,
    this.onDismissHelp,
  });

  final ValueChanged<HumorRating> onRated;
  final HumorRating? selected;
  final bool enabled;
  final String? subtitle;
  final VoidCallback? onDismissHelp;

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
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onDismissHelp != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.humorRatingHelpDismiss,
                    onPressed: onDismissHelp,
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final rating in HumorRating.binaryChoices)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: _BinaryRatingButton(
                      emoji: rating == HumorRating.funny ? '😂' : '😐',
                      label: rating == HumorRating.funny
                          ? l10n.humorRatingFunny
                          : l10n.humorRatingNotFunny,
                      selected: selected == rating,
                      enabled: enabled,
                      onTap: () => onRated(rating),
                      emphasizePositive: rating == HumorRating.funny,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BinaryRatingButton extends StatelessWidget {
  const _BinaryRatingButton({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.emphasizePositive,
  });

  final String emoji;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool emphasizePositive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = selected
        ? (emphasizePositive ? scheme.primary : scheme.secondaryContainer)
        : scheme.surfaceContainerHighest;
    final fg = selected
        ? (emphasizePositive ? scheme.onPrimary : scheme.onSecondaryContainer)
        : scheme.onSurface;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        elevation: selected ? 1 : 0,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
