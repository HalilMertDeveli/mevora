import 'package:flutter/material.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/features/profile/domain/catalog/hobby_catalog.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_multi_select_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';

class ProfileHobbyPicker extends StatelessWidget {
  const ProfileHobbyPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.showHint = true,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ProfileMultiSelectPicker(
      options: HobbyCatalog.values,
      selected: selected,
      onChanged: onChanged,
      enabled: enabled,
      maxSelection: HobbyCatalog.maxSelection,
      hint: showHint ? l10n.profileHobbiesHint : null,
      labelFor: (id) => OnboardingLabels.hobby(l10n, id),
    );
  }
}
