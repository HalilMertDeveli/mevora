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
bool learningPromptVisible(LearningSummary summary) => summary.invitesToday;

/// "Bugünün soruları hazır" — today's set on the Picks screen, until it is
/// answered or put away for today.
class LearningPromptCard extends StatelessWidget {
  const LearningPromptCard({
    super.key,
    required this.summary,
    required this.onOpen,
    this.onSkipToday,
  });

  final LearningSummary summary;
  final VoidCallback onOpen;

  /// "Bugünlük geç"; hidden when today's set cannot be skipped.
  final VoidCallback? onSkipToday;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = summary.today;
    final resuming = today.started;
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
            resuming
                ? l10n.learningCardTodayResume(today.answered, today.total)
                : l10n.learningCardTodayStart(today.total),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          if (resuming) ...[
            const SizedBox(height: AppSpacing.s12),
            MevoraMeter(value: today.answered / today.total),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (onSkipToday != null && today.canSkip) ...[
                Expanded(
                  child: MevoraButton(
                    key: const Key('learningSkipTodayCardButton'),
                    label: l10n.learningSkipToday,
                    variant: MevoraButtonVariant.ghost,
                    size: MevoraButtonSize.small,
                    onPressed: onSkipToday,
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
    final today = summary.today;
    final resuming = today.started;
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
            l10n.learningRequiredBody(today.total),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          if (resuming) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.learningProgress(today.answered, today.total),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            MevoraMeter(value: today.answered / today.total),
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
