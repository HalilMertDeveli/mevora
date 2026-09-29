import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/domain/services/shared_traits.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// "What you have in common": every answer both people share, one line each,
/// the topic first and the shared answer after it.
class SharedTraitsSection extends StatelessWidget {
  const SharedTraitsSection({super.key, required this.traits});

  final List<SharedTrait> traits;

  @override
  Widget build(BuildContext context) {
    if (traits.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.sharedTraitsTitle,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        for (final trait in traits)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: ExcludeSemantics(
                    child: Icon(
                      MevoraIcons.check,
                      size: 16,
                      color: p.compatibility,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: titleOf(l10n, trait.kind),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: '  ·  '),
                        TextSpan(text: valueOf(l10n, trait)),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String titleOf(AppLocalizations l10n, SharedTraitKind kind) {
    return switch (kind) {
      SharedTraitKind.relationshipGoal => l10n.sharedTraitGoal,
      SharedTraitKind.relationshipQuestions => l10n.sharedTraitQuestions,
      SharedTraitKind.children => l10n.sharedTraitChildren,
      SharedTraitKind.age => l10n.sharedTraitAge,
      SharedTraitKind.smoking => l10n.onboardingSmoking,
      SharedTraitKind.drinking => l10n.onboardingDrinking,
      SharedTraitKind.partnerExpectations => l10n.sharedTraitExpectations,
      SharedTraitKind.exercise => l10n.onboardingExercise,
      SharedTraitKind.diet => l10n.onboardingDiet,
      SharedTraitKind.pets => l10n.onboardingPets,
      SharedTraitKind.rhythm => l10n.sharedTraitRhythm,
      SharedTraitKind.socialLevel => l10n.profileSocialLevel,
      SharedTraitKind.livingTogether => l10n.profileCohabitationPreference,
      SharedTraitKind.weekend => l10n.profileWeekendPreferences,
      SharedTraitKind.interests => l10n.interests,
      SharedTraitKind.hobbies => l10n.sharedTraitHobbies,
      SharedTraitKind.languages => l10n.sharedTraitLanguages,
      SharedTraitKind.city => l10n.settingsCity,
    };
  }

  static String valueOf(AppLocalizations l10n, SharedTrait trait) {
    String list(String Function(AppLocalizations, String) label) =>
        trait.values.map((v) => label(l10n, v)).join(', ');
    int at(int i) => int.tryParse(trait.values[i]) ?? 0;
    return switch (trait.kind) {
      SharedTraitKind.relationshipGoal => OnboardingLabels.relationshipGoal(
        l10n,
        trait.value,
      ),
      SharedTraitKind.relationshipQuestions => l10n.sharedTraitQuestionsValue(
        at(0),
        at(1),
      ),
      SharedTraitKind.children => OnboardingLabels.childrenPreference(
        l10n,
        trait.value,
      ),
      SharedTraitKind.age => l10n.sharedTraitAgeValue(at(0), at(1)),
      SharedTraitKind.smoking ||
      SharedTraitKind.exercise ||
      SharedTraitKind.pets => OnboardingLabels.lifestyle(l10n, trait.value),
      SharedTraitKind.drinking => OnboardingLabels.alcohol(l10n, trait.value),
      SharedTraitKind.partnerExpectations => l10n.sharedTraitExpectationsValue,
      SharedTraitKind.diet => OnboardingLabels.diet(l10n, trait.value),
      SharedTraitKind.rhythm => OnboardingLabels.socialRhythm(
        l10n,
        trait.value,
      ),
      SharedTraitKind.socialLevel => OnboardingLabels.socialLevel(
        l10n,
        trait.value,
      ),
      SharedTraitKind.livingTogether => OnboardingLabels.cohabitation(
        l10n,
        trait.value,
      ),
      SharedTraitKind.weekend => list(OnboardingLabels.weekendPreference),
      SharedTraitKind.interests => list(OnboardingLabels.interest),
      SharedTraitKind.hobbies => list(OnboardingLabels.hobby),
      SharedTraitKind.languages => list(OnboardingLabels.language),
      SharedTraitKind.city => trait.value ?? '',
    };
  }
}
