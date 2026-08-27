import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_education_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Compact progress strip shown while the humor profile is still learning.
class HumorLearningProgressBanner extends StatelessWidget {
  const HumorLearningProgressBanner({
    super.key,
    required this.profile,
  });

  final UserHumorProfile profile;

  @override
  Widget build(BuildContext context) {
    if (!profile.profileBuilding &&
        profile.interactionCount >= HumorFeedPolicy.buildingThreshold) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = HumorEducationPolicy.learningProgress(
      profile.interactionCount,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.humorProgressTitle,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.humorProgressCount(profile.interactionCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
