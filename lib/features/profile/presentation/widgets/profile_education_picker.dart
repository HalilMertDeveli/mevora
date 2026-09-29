import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileEducationPicker extends StatelessWidget {
  const ProfileEducationPicker({
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
    return Semantics(
      container: true,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final option in OnboardingEducation.values)
            Semantics(
              inMutuallyExclusiveGroup: true,
              child: MevoraChip(
                label: OnboardingLabels.education(l10n, option),
                selected: value == option,
                onSelected: enabled ? (_) => onChanged(option) : null,
              ),
            ),
        ],
      ),
    );
  }
}
