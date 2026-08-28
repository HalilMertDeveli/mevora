import 'package:flutter/material.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/entities/hidden_compatibility_insight.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_reveal_section.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/l10n/app_localizations.dart';
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
    return MevoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.hiddenCompatTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.hiddenCompatMessage(insight.alignedCount),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.hiddenCompatCompatibility(insight.overallScore),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraButton(label: l10n.hiddenCompatCta, onPressed: onDiscover),
          const SizedBox(height: AppSpacing.xs),
          MevoraButton(
            label: l10n.hiddenCompatDismiss,
            variant: MevoraButtonVariant.ghost,
            onPressed: onDismiss,
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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: SingleChildScrollView(
            child: CompatibilityRevealSection(
              breakdown: breakdown,
              reasons: reasons,
            ),
          ),
        ),
      );
    },
  );
}
