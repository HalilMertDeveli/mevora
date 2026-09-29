import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/copy/pick_copy.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_type_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// "Why {name}?" — every reason Mevora had for this Pick, one line each.
///
/// Drawn as the same sage card as the profile's compatibility card
/// ("Why you're seeing this"), so the two explanations read as one family.
class PickWhySection extends StatelessWidget {
  const PickWhySection({super.key, required this.pick});

  final MevoraPick pick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final lines = PickCopy.whyLines(l10n, pick);
    return MevoraCard(
      color: p.compatibilityContainer.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.pickWhyTitle(pick.candidate.displayName),
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.xs + 2,
            runSpacing: AppSpacing.xs + 2,
            children: [
              PickTypeBadge(type: pick.pickType),
              for (final label in pick.secondaryLabels)
                PickTypeBadge(type: label, emphasized: false),
            ],
          ),
          if (lines.isNotEmpty) const SizedBox(height: AppSpacing.md),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: ExcludeSemantics(
                      child: Icon(line.icon, size: 16, color: p.compatibility),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      line.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
