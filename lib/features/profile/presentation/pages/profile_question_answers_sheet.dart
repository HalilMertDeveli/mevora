import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_display.dart';
import 'package:mevora/l10n/app_localizations.dart';

Future<void> showProfileQuestionAnswersSheet(
  BuildContext context, {
  required String uid,
  required bool isOwner,
  required List<ProfileQuestionAnswer> answers,
}) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  final cards = answers
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
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cards.length,
                  separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.md),
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
