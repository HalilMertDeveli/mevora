import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_meter.dart';

/// Whether [summary] has anything to invite the member to right now.
bool learningPromptVisible(LearningSummary summary) =>
    summary.invitesInitial ||
    (summary.initialCompleted && summary.progressiveDue);

/// "Mevora seni biraz daha tanısın" — an optional invitation on the Picks
/// screen. Existing members see it until they finish the initial questions;
/// afterwards it appears only when a follow-up round is due, and "Not now"
/// puts it away for days.
class LearningPromptCard extends StatelessWidget {
  const LearningPromptCard({
    super.key,
    required this.summary,
    required this.onOpen,
    this.onNotNow,
  });

  final LearningSummary summary;
  final VoidCallback onOpen;

  /// Only offered for follow-up rounds.
  final VoidCallback? onNotNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final initial = !summary.initialCompleted;
    final resuming = initial && summary.initialAnswered > 0;
    final body = initial
        ? resuming
              ? l10n.learningCardInitialResume(
                  summary.initialAnswered,
                  summary.initialTotal,
                )
              : l10n.learningCardInitialStart(summary.initialTotal)
        : l10n.learningCardFollowUp(summary.followUpSize);
    return MevoraCard(
      key: const Key('learningPromptCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(MevoraIcons.questions),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  l10n.learningCardTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          if (resuming) ...[
            const SizedBox(height: AppSpacing.s12),
            MevoraMeter(value: summary.initialAnswered / summary.initialTotal),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (!initial && onNotNow != null) ...[
                Expanded(
                  child: MevoraButton(
                    key: const Key('learningNotNowButton'),
                    label: l10n.learningCardNotNow,
                    variant: MevoraButtonVariant.ghost,
                    size: MevoraButtonSize.small,
                    onPressed: onNotNow,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
              ],
              Expanded(
                child: MevoraButton(
                  key: const Key('learningOpenButton'),
                  label: resuming
                      ? l10n.learningCardResume
                      : l10n.learningCardStart,
                  variant: MevoraButtonVariant.tonal,
                  size: MevoraButtonSize.small,
                  onPressed: onOpen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A new member's Picks screen before their first set: the questions come
/// first, because today's people are chosen from the answers.
class LearningGate extends StatelessWidget {
  const LearningGate({super.key, required this.summary, required this.onOpen});

  final LearningSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final resuming = summary.initialAnswered > 0;
    return Padding(
      key: const Key('learningGate'),
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const MevoraSpot(art: MevoraArt.questions),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.learningRequiredTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.learningRequiredBody(summary.initialTotal),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          if (resuming) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.learningProgress(
                summary.initialAnswered,
                summary.initialTotal,
              ),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            MevoraMeter(value: summary.initialAnswered / summary.initialTotal),
          ],
          const SizedBox(height: AppSpacing.xl),
          MevoraButton(
            key: const Key('learningGateButton'),
            label: resuming ? l10n.learningCardResume : l10n.learningIntroStart,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}
