import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/profile/domain/services/profile_completion_calculator.dart';
import 'package:mevora/features/profile/presentation/profile_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';

class ProfileCompletionBanner extends StatelessWidget {
  const ProfileCompletionBanner({
    super.key,
    required this.result,
  });

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
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.profileCompletionTitle(result.percent),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: result.percent / 100),
            if (missingLabels.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.profileCompletionMissing(missingLabels),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
