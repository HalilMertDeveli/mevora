import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/matching_streak/domain/entities/matching_streak.dart';
import 'package:mevora/features/matching_streak/domain/repositories/matching_streak_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';

class MatchingStreakTile extends StatelessWidget {
  const MatchingStreakTile({
    super.key,
    required this.uid,
    required this.repository,
  });

  final String uid;
  final MatchingStreakRepository repository;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<MatchingStreak>(
      stream: repository.watchStreak(uid),
      builder: (context, snapshot) {
        final streak = snapshot.data ?? MatchingStreak.empty;
        final title = streak.currentStreak <= 0
            ? l10n.matchingStreakEmptyTitle
            : l10n.matchingStreakTitle(streak.currentStreak);
        final subtitle = streak.dailyParticipation
            ? l10n.matchingStreakKeptToday
            : l10n.matchingStreakKeepPrompt;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: ListTile(
              leading: Text(
                '🔥',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: streak.longestStreak > 0
                  ? Text(
                      l10n.matchingStreakBest(streak.longestStreak),
                      style: Theme.of(context).textTheme.labelMedium,
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}
