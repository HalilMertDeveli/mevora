// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';

class ProfileRelationshipGoalPicker extends StatelessWidget {
  const ProfileRelationshipGoalPicker({
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
    return Column(
      children: [
        for (final option in OnboardingRelationshipGoal.values)
          RadioListTile<String>(
            value: option,
            groupValue: value,
            title: Text(OnboardingLabels.relationshipGoal(l10n, option)),
            onChanged: enabled ? (next) => onChanged(next!) : null,
          ),
      ],
    );
  }
}
