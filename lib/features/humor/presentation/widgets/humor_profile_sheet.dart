import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/l10n/app_localizations.dart';

class HumorProfileSheet extends StatelessWidget {
  const HumorProfileSheet({
    super.key,
    required this.profile,
    this.analytics,
  });

  final UserHumorProfile profile;
  final Future<void> Function(String name)? analytics;

  static Future<void> show(
    BuildContext context, {
    required UserHumorProfile profile,
    Future<void> Function(String name)? analytics,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HumorProfileSheet(
        profile: profile,
        analytics: analytics,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vibes = HumorProfileDisplay.visibleTopVibes(profile, max: 5);
    final progress = HumorFeedPolicy.buildingProgress(profile);
    final hasEnoughData =
        !profile.profileBuilding && profile.interactionCount > 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                  hasEnoughData
                      ? l10n.humorProfileReadyTitle
                      : l10n.humorProfileEmptyData,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (!hasEnoughData) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.humorProgressCount(profile.interactionCount),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.humorProfileNotReady,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                Text(
                  l10n.humorFavoriteHumor,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (vibes.isEmpty)
                  Text(
                    l10n.humorProfileEmptyData,
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  for (final vibe in vibes) ...[
                    Text(
                      HumorProfileDisplay.categoryLabel(l10n, vibe.category),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (vibe.value.clamp(0, 100)) / 100,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.humorProfileHowForms,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.humorWhyMattersTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.humorWhyMattersBody1,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.humorWhyMattersBody2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(l10n.humorHowCalculatedTitle),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.humorHowCalculatedBody,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                onExpansionChanged: (open) {
                  if (open) {
                    final cb = analytics;
                    if (cb != null) {
                      unawaited(cb('humor_rating_help_viewed'));
                    }
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.humorPrivacyNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
