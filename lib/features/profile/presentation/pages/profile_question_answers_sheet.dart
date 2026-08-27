import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_display.dart';
import 'package:mevora/l10n/app_localizations.dart';

Future<void> showProfileQuestionAnswersSheet(
  BuildContext context, {
  required String uid,
  required bool isOwner,
  required List<ProfileQuestionAnswer> answers,
  bool premiumLocked = false,
}) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  // When premium-locked, never resolve answer text even if a stale answerId
  // sneaks into the list (defense in depth vs CF / parser bugs).
  final safeAnswers = premiumLocked && !isOwner
      ? answers
          .map(
            (item) => ProfileQuestionAnswer(
              questionId: item.questionId,
              answerId: '',
              isVisible: item.isVisible,
              answerLocked: true,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
            ),
          )
          .toList(growable: false)
      : answers;
  final cards = safeAnswers
      .map((item) => ProfileQuestionAnswerDisplay.resolve(item, locale))
      .whereType<ProfileQuestionAnswerDisplay>()
      .toList(growable: false);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.questionAnswersTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (premiumLocked) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.questionAnswersPremiumLockedMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.boost),
                    child: Text(l10n.questionAnswersPremiumUnlockCta),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cards.length,
                  separatorBuilder: (_, index) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.questionText,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        if (card.isLocked || premiumLocked)
                          Text(
                            l10n.questionAnswersPremiumAnswerHidden,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else
                          Text(
                            '"${card.answerText}"',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
