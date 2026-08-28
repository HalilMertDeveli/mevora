import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/compatibility/presentation/widgets/animated_compatibility_score.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_category_bars.dart';
import 'package:mevora/l10n/app_localizations.dart';

enum CompatibilityRevealDensity { full, compact }

/// Premium compatibility reveal — score, categories, and reasons from real data.
class CompatibilityRevealSection extends StatelessWidget {
  const CompatibilityRevealSection({
    super.key,
    required this.breakdown,
    required this.reasons,
    this.density = CompatibilityRevealDensity.full,
    this.showReasons = true,
    this.onWhyTap,
  });

  final CompatibilityBreakdown breakdown;
  final List<CompatibilityReason> reasons;
  final CompatibilityRevealDensity density;
  final bool showReasons;
  final VoidCallback? onWhyTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (breakdown.dataQuality == CompatibilityDataQuality.insufficient) {
      return Text(
        l10n.compatNotEnoughData,
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      );
    }

    final bars = compatibilityCategoryBarsFromBreakdown(
      context,
      breakdown,
      maxBars: density == CompatibilityRevealDensity.compact ? 3 : 5,
    );
    final strongest = compatibilityStrongestLabel(l10n, breakdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedCompatibilityScore(
            target: breakdown.overallScore,
            label: l10n.compatScoreHeading,
            compact: density == CompatibilityRevealDensity.compact,
          ),
        ),
        if (strongest != null &&
            density == CompatibilityRevealDensity.full) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.matchStrongestConnectionLabel(strongest),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.softGreen,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.whyYouMatch,
          style: density == CompatibilityRevealDensity.compact
              ? theme.textTheme.titleSmall
              : theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...bars,
        if (showReasons && reasons.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final reason in reasons.take(
            density == CompatibilityRevealDensity.compact ? 2 : 4,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    size: 18,
                    color: AppColors.softGreen,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      CompatibilityL10n.reason(l10n, reason),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (onWhyTap != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
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
          ),
        ],
      ],
    );
  }
}
