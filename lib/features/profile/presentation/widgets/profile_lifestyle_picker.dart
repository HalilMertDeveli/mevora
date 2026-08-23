import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileLifestylePicker extends StatelessWidget {
  const ProfileLifestylePicker({
    super.key,
    required this.profile,
    required this.onChanged,
    this.enabled = true,
  });

  final ProfileLifestyle profile;
  final ValueChanged<ProfileLifestyle> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _group(
          context,
          l10n.onboardingSmoking,
          profile.smoking,
          OnboardingLifestyleOption.habitValues,
          (value) => onChanged(profile.copyWith(smoking: value)),
          l10n,
        ),
        _group(
          context,
          l10n.onboardingDrinking,
          profile.drinking,
          OnboardingLifestyleOption.habitValues,
          (value) => onChanged(profile.copyWith(drinking: value)),
          l10n,
        ),
        _group(
          context,
          l10n.onboardingExercise,
          profile.exercise,
          OnboardingLifestyleOption.habitValues,
          (value) => onChanged(profile.copyWith(exercise: value)),
          l10n,
        ),
        _group(
          context,
          l10n.onboardingPets,
          profile.pets,
          OnboardingLifestyleOption.petValues,
          (value) => onChanged(profile.copyWith(pets: value)),
          l10n,
        ),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    String? selected,
    List<String> values,
    ValueChanged<String> onChanged,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in values)
                MevoraChip(
                  label: OnboardingLabels.lifestyle(l10n, value),
                  selected: selected == value,
                  onSelected: enabled ? (_) => onChanged(value) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
