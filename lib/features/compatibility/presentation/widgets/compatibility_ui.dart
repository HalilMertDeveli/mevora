import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/entities/hidden_compatibility_insight.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/compatibility/presentation/widgets/animated_compatibility_score.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

class WhyYouMatchPanel extends StatelessWidget {
  const WhyYouMatchPanel({
    super.key,
    required this.breakdown,
    required this.reasons,
  });

  final CompatibilityBreakdown breakdown;
  final List<CompatibilityReason> reasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (breakdown.dataQuality == CompatibilityDataQuality.insufficient) {
      return Text(l10n.compatNotEnoughData, style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedCompatibilityScore(
            target: breakdown.overallScore,
            label: l10n.compatOverallLabel(breakdown.overallScore),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.whyYouMatch,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        _CategoryRow(
          label: l10n.compatCategoryRelationship,
          score: breakdown.relationshipScore,
          icon: Icons.favorite_rounded,
        ),
        _CategoryRow(
          label: l10n.compatCategoryInterests,
          score: breakdown.interestScore,
          icon: Icons.interests_outlined,
        ),
        if (breakdown.languageScore != null)
          _CategoryRow(
            label: l10n.compatCategoryLanguages,
            score: breakdown.languageScore!,
            icon: Icons.translate_outlined,
          ),
        if (breakdown.hobbyScore != null)
          _CategoryRow(
            label: l10n.compatCategoryHobbies,
            score: breakdown.hobbyScore!,
            icon: Icons.sports_kabaddi_outlined,
          ),
        _CategoryRow(
          label: l10n.compatCategoryLifestyle,
          score: breakdown.lifestyleScore,
          icon: Icons.self_improvement_outlined,
        ),
        if (breakdown.valuesScore != null)
          _CategoryRow(
            label: l10n.compatCategoryValues,
            score: breakdown.valuesScore!,
            icon: Icons.favorite_border_outlined,
          ),
        if (breakdown.questionScore != null)
          _CategoryRow(
            label: l10n.compatCategoryQuestions,
            score: breakdown.questionScore!,
            icon: Icons.psychology_outlined,
          ),
        if (breakdown.musicScore != null)
          _CategoryRow(
            label: l10n.compatCategoryMusic,
            score: breakdown.musicScore!,
            icon: Icons.music_note_outlined,
          ),
        const SizedBox(height: AppSpacing.md),
        for (final reason in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    CompatibilityL10n.reason(l10n, reason),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (breakdown.strongestCategory != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.compatStrongestConnection,
            style: theme.textTheme.labelLarge,
          ),
          Text(
            CompatibilityL10n.category(l10n, breakdown.strongestCategory!),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (breakdown.weakestCategory != null &&
            breakdown.weakestCategory != breakdown.strongestCategory) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.compatPotentialDifference,
            style: theme.textTheme.labelLarge,
          ),
          Text(
            CompatibilityL10n.category(l10n, breakdown.weakestCategory!),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.score,
    required this.icon,
  });

  final String label;
  final int score;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text('$score%', style: theme.textTheme.titleSmall),
        ],
      ),
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
            child: WhyYouMatchPanel(breakdown: breakdown, reasons: reasons),
          ),
        ),
      );
    },
  );
}
