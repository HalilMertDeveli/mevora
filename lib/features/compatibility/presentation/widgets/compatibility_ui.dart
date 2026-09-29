import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/entities/hidden_compatibility_insight.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_reveal_section.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

export 'compatibility_reveal_section.dart';

class WhyYouMatchPanel extends StatelessWidget {
  const WhyYouMatchPanel({
    super.key,
    required this.breakdown,
    required this.reasons,
    this.compact = false,
  });

  final CompatibilityBreakdown breakdown;
  final List<CompatibilityReason> reasons;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CompatibilityRevealSection(
      breakdown: breakdown,
      reasons: reasons,
      density: compact
          ? CompatibilityRevealDensity.compact
          : CompatibilityRevealDensity.full,
    );
  }
}

/// A quiet nudge above the deck: someone you passed over agrees with you on
/// more than you might think.
class HiddenCompatibilityCard extends StatelessWidget {
  const HiddenCompatibilityCard({
    super.key,
    required this.insight,
    required this.onDiscover,
    required this.onDismiss,
  });

  final HiddenCompatibilityInsight insight;
  final VoidCallback onDiscover;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    return MevoraCard(
      color: p.compatibilityContainer,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.s12,
        AppSpacing.xs,
        AppSpacing.s12,
      ),
      child: Row(
        children: [
          CompatibilityRing(score: insight.overallScore, size: 44),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.hiddenCompatTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: p.onCompatibilityContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.hiddenCompatMessage(insight.alignedCount),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.onCompatibilityContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                MevoraButton(
                  label: l10n.hiddenCompatCta,
                  size: MevoraButtonSize.small,
                  variant: MevoraButtonVariant.secondary,
                  isExpanded: false,
                  onPressed: onDiscover,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.hiddenCompatDismiss,
            onPressed: onDismiss,
            icon: Icon(
              MevoraIcons.close,
              size: 18,
              color: p.onCompatibilityContainer,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCompatibilityBreakdownSheet(
  BuildContext context, {
  required CompatibilityBreakdown breakdown,
  required List<CompatibilityReason> reasons,
}) {
  return MevoraBottomSheet.show<void>(
    context,
    scrollable: true,
    child: CompatibilityRevealSection(
      breakdown: breakdown,
      reasons: reasons,
      framed: false,
    ),
  );
}
