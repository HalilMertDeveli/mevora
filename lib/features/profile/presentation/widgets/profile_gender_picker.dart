import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileGenderPicker extends StatelessWidget {
  const ProfileGenderPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final option in OnboardingGender.values)
          MevoraChip(
            label: OnboardingLabels.gender(l10n, option),
            selected: value == option,
            onSelected: enabled ? (_) => onChanged(option) : null,
          ),
      ],
    );
  }
}

class ProfileInterestedInPicker extends StatelessWidget {
  const ProfileInterestedInPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final option in OnboardingInterestedIn.values)
          MevoraChip(
            label: OnboardingLabels.interestedIn(l10n, option),
            selected: value == option,
            onSelected: enabled ? (_) => onChanged(option) : null,
          ),
      ],
    );
  }
}
