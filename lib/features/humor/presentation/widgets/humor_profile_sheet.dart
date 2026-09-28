import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class HumorProfileSheet extends StatelessWidget {
  const HumorProfileSheet({super.key, required this.profile});

  final UserHumorProfile profile;

  static Future<void> show(
    BuildContext context, {
    required UserHumorProfile profile,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HumorProfileSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Only traits with real signal, named with a strength word. A dimension
    // near the neutral midpoint is "no evidence", not a trait, and a number
    // would claim a precision a few ratings cannot give.
    final vibes = HumorProfileDisplay.visibleTopVibes(profile)
        .where(
          (vibe) =>
              HumorProfileDisplay.strengthOf(vibe.value) != HumorStrength.low,
        )
        .toList();
    final progress = HumorFeedPolicy.buildingProgress(profile);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              HumorProfileDisplay.buildingLabel(l10n, profile),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (profile.profileBuilding) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.humorProfileBuilding,
                style: theme.textTheme.bodyMedium,
              ),
            ] else ...[
              Text(l10n.humorTopVibes, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (vibes.isEmpty)
                Text(
                  l10n.humorResultSummaryNone,
                  style: theme.textTheme.bodyMedium,
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final vibe in vibes)
                      MevoraChip(
                        label:
                            '${HumorProfileDisplay.categoryLabel(l10n, vibe.category)} · '
                            '${HumorProfileDisplay.strengthLabel(l10n, HumorProfileDisplay.strengthOf(vibe.value))}',
                        selected: true,
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
