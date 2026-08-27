import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/profile/domain/services/profile_quality_calculator.dart';
import 'package:mevora/features/profile/presentation/profile_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Shows "Profile Quality N%" with actionable missing items.
class ProfileQualityCard extends StatelessWidget {
  const ProfileQualityCard({
    super.key,
    required this.result,
    this.compact = false,
  });

  final ProfileQualityResult result;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final missingLabels = result.missingFieldKeys
        .take(4)
        .map((key) => ProfileLabels.qualityField(l10n, key))
        .where((label) => label.isNotEmpty)
        .join(', ');

    return Card(
      margin: EdgeInsets.only(bottom: compact ? AppSpacing.md : AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.profileQualityTitle(result.score),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: result.score / 100),
            if (missingLabels.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.profileQualityMissing(missingLabels),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Soft Boost tip — never disables purchase actions.
class ProfileQualityBoostHint extends StatelessWidget {
  const ProfileQualityBoostHint({
    super.key,
    required this.result,
  });

  final ProfileQualityResult result;

  @override
  Widget build(BuildContext context) {
    if (result.score >= 80 || result.missingFieldKeys.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tip = result.missingFieldKeys
        .take(2)
        .map((key) => ProfileLabels.qualityField(l10n, key))
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        l10n.profileQualityBoostHint(tip),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
