import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_filters.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

abstract final class DiscoveryFiltersSheet {
  static Future<DiscoveryFilters?> show(
    BuildContext context, {
    required DiscoveryFilters initial,
  }) {
    return MevoraBottomSheet.show<DiscoveryFilters>(
      context,
      title: AppLocalizations.of(context).discoveryFiltersTitle,
      child: _DiscoveryFiltersBody(initial: initial),
    );
  }
}

class _DiscoveryFiltersBody extends StatefulWidget {
  const _DiscoveryFiltersBody({required this.initial});

  final DiscoveryFilters initial;

  @override
  State<_DiscoveryFiltersBody> createState() => _DiscoveryFiltersBodyState();
}

class _DiscoveryFiltersBodyState extends State<_DiscoveryFiltersBody> {
  late RangeValues _ageRange;
  late double _distance;
  late String? _gender;
  late String? _relationshipGoal;

  @override
  void initState() {
    super.initState();
    _ageRange = RangeValues(
      widget.initial.minAge.toDouble(),
      widget.initial.maxAge.toDouble(),
    );
    _distance = widget.initial.maxDistanceKm;
    _gender = widget.initial.gender;
    _relationshipGoal = widget.initial.relationshipGoal;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.filterAge, style: theme.textTheme.titleSmall),
        RangeSlider(
          values: _ageRange,
          min: 18,
          max: 60,
          divisions: 42,
          labels: RangeLabels(
            _ageRange.start.round().toString(),
            _ageRange.end.round().toString(),
          ),
          onChanged: (values) => setState(() => _ageRange = values),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.filterDistance, style: theme.textTheme.titleSmall),
        Slider(
          value: _distance,
          min: 5,
          max: 100,
          divisions: 19,
          label: '${_distance.round()} km',
          onChanged: (value) => setState(() => _distance = value),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.filterGender, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final option in const ['woman', 'man', 'nonBinary'])
              ChoiceChip(
                label: Text(_genderLabel(l10n, option)),
                selected: _gender == option,
                onSelected: (selected) {
                  setState(() => _gender = selected ? option : null);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.filterRelationshipGoal, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final option in const ['longTerm', 'casual', 'figuringOut'])
              ChoiceChip(
                label: Text(_goalLabel(l10n, option)),
                selected: _relationshipGoal == option,
                onSelected: (selected) {
                  setState(() => _relationshipGoal = selected ? option : null);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.discoveryFiltersHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        MevoraButton(
          label: l10n.applyFilters,
          onPressed: () {
            Navigator.of(context).pop(
              DiscoveryFilters(
                minAge: _ageRange.start.round(),
                maxAge: _ageRange.end.round(),
                maxDistanceKm: _distance,
                gender: _gender,
                relationshipGoal: _relationshipGoal,
              ),
            );
          },
        ),
      ],
    );
  }

  String _genderLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      'woman' => l10n.genderWoman,
      'man' => l10n.genderMan,
      'nonBinary' => l10n.genderNonBinary,
      _ => value,
    };
  }

  String _goalLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      'longTerm' => l10n.relationshipGoalLongTerm,
      'casual' => l10n.relationshipGoalCasual,
      'figuringOut' => l10n.relationshipGoalFiguringOut,
      _ => value,
    };
  }
}
