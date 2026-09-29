import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/profile/domain/services/profile_completion_calculator.dart';
import 'package:mevora/features/profile/presentation/profile_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_meter.dart';

/// How complete the profile is, and what is still missing — shown only while
/// something is.
class ProfileCompletionBanner extends StatelessWidget {
  const ProfileCompletionBanner({super.key, required this.result});

  final ProfileCompletionResult result;

  @override
  Widget build(BuildContext context) {
    if (result.isComplete) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final missingLabels = result.missingFieldKeys
        .take(4)
        .map((key) => ProfileLabels.completionField(l10n, key))
        .join(', ');
    return MevoraCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Why first; the percentage is progress detail, not the reason.
          Text(
            l10n.profileCompletionHeadline,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.profileCompletionBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          MevoraMeter(
            value: result.percent / 100,
            trackColor: context.palette.surface,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.profileCompletionTitle(result.percent),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          if (missingLabels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.profileCompletionMissing(missingLabels),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
