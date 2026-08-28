import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Prominent compatibility score for discovery cards (Mevora 2.0).
class DiscoveryCompatibilityScore extends StatelessWidget {
  const DiscoveryCompatibilityScore({
    super.key,
    required this.score,
    this.status = CompatibilityDisplayStatus.ready,
    this.onWhyTap,
  });

  final int score;
  final CompatibilityDisplayStatus status;
  final VoidCallback? onWhyTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (status == CompatibilityDisplayStatus.calculating) {
      return Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.compatCalculating,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (status == CompatibilityDisplayStatus.unavailable) {
      return Text(
        l10n.compatUnavailable,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$score%',
          style: theme.textTheme.displayMedium?.copyWith(
            color: AppColors.softGreen,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.compatScoreHeading,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onWhyTap != null) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onWhyTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: theme.colorScheme.secondary,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.whyYouMatch,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact compatibility chip for legacy surfaces.
class CompatibilityDiscoverBadge extends StatelessWidget {
  const CompatibilityDiscoverBadge({
    super.key,
    required this.score,
    this.status = CompatibilityDisplayStatus.ready,
    this.onTap,
  });

  final int score;
  final CompatibilityDisplayStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final label = switch (status) {
      CompatibilityDisplayStatus.calculating => l10n.compatCalculating,
      CompatibilityDisplayStatus.unavailable => l10n.compatUnavailable,
      CompatibilityDisplayStatus.ready => l10n.compatDiscoverBadge(score),
    };

    final canTap = status == CompatibilityDisplayStatus.ready && onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            color: AppColors.softGreen.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.softGreen.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == CompatibilityDisplayStatus.calculating)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.tertiary,
                  ),
                )
              else
                Icon(
                  status == CompatibilityDisplayStatus.unavailable
                      ? Icons.info_outline
                      : Icons.insights_outlined,
                  size: 14,
                  color: AppColors.softGreen,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
