import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/l10n/app_localizations.dart';

class DiscoveryCategoryBar extends StatelessWidget {
  const DiscoveryCategoryBar({
    super.key,
    required this.label,
    required this.score,
  });

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (score / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.outline.withValues(alpha: 0.5),
                color: AppColors.softGreen,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Text(
              '$score%',
              textAlign: TextAlign.end,
              maxLines: 1,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds up to three category bars from server breakdown data.
List<Widget> discoveryCategoryBars(
  BuildContext context,
  DiscoveryCandidate candidate,
) {
  final l10n = AppLocalizations.of(context);
  final entries = <({String label, int score})>[];

  void add(String label, int? score) {
    if (score != null && score > 0) {
      entries.add((label: label, score: score));
    }
  }

  add(l10n.compatCategoryRelationship, candidate.categoryRelationshipScore);
  add(l10n.compatCategoryLifestyle, candidate.categoryLifestyleScore);
  add(l10n.compatCategoryMusic, candidate.categoryMusicScore);
  add(l10n.compatCategoryQuestions, candidate.categoryQuestionScore);
  add(l10n.compatCategoryInterests, candidate.categoryInterestScore);
  add(l10n.compatCategoryCommunication, candidate.categoryCommunicationScore);

  entries.sort((a, b) => b.score.compareTo(a.score));
  return entries
      .take(3)
      .map(
        (e) => DiscoveryCategoryBar(label: e.label, score: e.score),
      )
      .toList();
}
