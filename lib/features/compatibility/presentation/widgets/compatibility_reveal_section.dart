import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_category_bars.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

enum CompatibilityRevealDensity { full, compact }

/// "Why you fit" — the reasoning first, the number second.
///
/// Header: the score ring beside the strongest connection in words. Then the
/// individual signals as tone-coded meters, then the concrete reasons Mevora
/// found (shared answers, artists, interests). All from real data.
class CompatibilityRevealSection extends StatelessWidget {
  const CompatibilityRevealSection({
    super.key,
    required this.breakdown,
    required this.reasons,
    this.density = CompatibilityRevealDensity.full,
    this.showReasons = true,
    this.onWhyTap,
    this.framed = true,
  });

  final CompatibilityBreakdown breakdown;
  final List<CompatibilityReason> reasons;
  final CompatibilityRevealDensity density;
  final bool showReasons;
  final VoidCallback? onWhyTap;

  /// Wrap in a sage-tinted card. Off when the host already provides a frame.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    final compact = density == CompatibilityRevealDensity.compact;

    if (breakdown.dataQuality == CompatibilityDataQuality.insufficient) {
      return Text(
        l10n.compatNotEnoughData,
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      );
    }

    final signals = compatibilitySignalsFromBreakdown(
      breakdown,
      limit: compact ? 3 : 5,
    );
    final strongest = compatibilityStrongestLabel(l10n, breakdown);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CompatibilityRing(
              score: breakdown.overallScore,
              size: compact ? 52 : 64,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.whyYouMatch,
                      style: compact
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium,
                    ),
                  ),
                  if (strongest != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.matchStrongestConnectionLabel(strongest),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.onCompatibilityContainer,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (signals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          for (final signal in signals) CompatibilitySignalBar(signal: signal),
        ],
        if (showReasons && reasons.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          for (final reason in reasons.take(compact ? 2 : 4))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      MevoraIcons.check,
                      size: 16,
                      color: p.compatibility,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      CompatibilityL10n.reason(l10n, reason),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.textPrimary,
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (onWhyTap != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onWhyTap,
              style: TextButton.styleFrom(
                foregroundColor: p.compatibility,
                padding: EdgeInsets.zero,
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(MevoraIcons.chevronRight, size: 16),
              label: Text(l10n.whyYouMatch),
            ),
          ),
      ],
    );

    if (!framed) return content;
    return MevoraCard(
      color: p.compatibilityContainer.withValues(alpha: 0.55),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: content,
    );
  }
}
