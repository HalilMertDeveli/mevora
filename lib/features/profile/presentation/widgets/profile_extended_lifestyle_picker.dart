import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_multi_select_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileExtendedLifestylePicker extends StatelessWidget {
  const ProfileExtendedLifestylePicker({
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
        _singleGroup(
          context,
          l10n.profilePartnerSmokingPref,
          profile.partnerSmokingPref,
          PartnerPreference.values,
          (value) => onChanged(profile.copyWith(partnerSmokingPref: value)),
          OnboardingLabels.partnerPreference,
        ),
        _singleGroup(
          context,
          l10n.profilePartnerDrinkingPref,
          profile.partnerDrinkingPref,
          PartnerPreference.values,
          (value) => onChanged(profile.copyWith(partnerDrinkingPref: value)),
          OnboardingLabels.partnerPreference,
        ),
        _singleGroup(
          context,
          l10n.profileChildrenPreference,
          profile.childrenPreference,
          ChildrenPreference.values,
          (value) => onChanged(profile.copyWith(childrenPreference: value)),
          OnboardingLabels.childrenPreference,
        ),
        _singleGroup(
          context,
          l10n.profilePartnerChildrenPref,
          profile.partnerChildrenPref,
          PartnerPreference.values,
          (value) => onChanged(profile.copyWith(partnerChildrenPref: value)),
          OnboardingLabels.partnerPreference,
        ),
        _singleGroup(
          context,
          l10n.profileSocialRhythm,
          profile.socialRhythm,
          SocialRhythm.values,
          (value) => onChanged(profile.copyWith(socialRhythm: value)),
          OnboardingLabels.socialRhythm,
        ),
        _singleGroup(
          context,
          l10n.profileSocialLevel,
          profile.socialLevel,
          SocialLevel.values,
          (value) => onChanged(profile.copyWith(socialLevel: value)),
          OnboardingLabels.socialLevel,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.profileWeekendPreferences,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              ProfileMultiSelectPicker(
                options: WeekendPreference.values,
                selected: profile.weekendPreferences.toSet(),
                onChanged: (next) =>
                    onChanged(profile.copyWith(weekendPreferences: next.toList())),
                enabled: enabled,
                maxSelection: 6,
                labelFor: (id) => OnboardingLabels.weekendPreference(l10n, id),
              ),
            ],
          ),
        ),
        _singleGroup(
          context,
          l10n.profileCohabitationPreference,
          profile.cohabitationPreference,
          CohabitationPreference.values,
          (value) => onChanged(profile.copyWith(cohabitationPreference: value)),
          OnboardingLabels.cohabitation,
        ),
      ],
    );
  }

  Widget _singleGroup(
    BuildContext context,
    String title,
    String? selected,
    List<String> values,
    ValueChanged<String> onChanged,
    String Function(AppLocalizations, String?) labelFor,
  ) {
    final l10n = AppLocalizations.of(context);
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
                  label: labelFor(l10n, value),
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
