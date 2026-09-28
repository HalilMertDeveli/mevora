import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_filters.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

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
        _FilterLabel(
          l10n.filterAge,
          value: '${_ageRange.start.round()}–${_ageRange.end.round()}',
        ),
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
        const SizedBox(height: AppSpacing.md),
        _FilterLabel(l10n.filterDistance, value: '${_distance.round()} km'),
        Slider(
          value: _distance,
          min: 5,
          max: 100,
          divisions: 19,
          label: '${_distance.round()} km',
          onChanged: (value) => setState(() => _distance = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _FilterLabel(l10n.filterGender),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in const ['woman', 'man', 'nonBinary'])
              MevoraChip(
                label: _genderLabel(l10n, option),
                selected: _gender == option,
                onSelected: (selected) {
                  setState(() => _gender = selected ? option : null);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _FilterLabel(l10n.filterRelationshipGoal),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in const ['longTerm', 'casual', 'figuringOut'])
              MevoraChip(
                label: _goalLabel(l10n, option),
                selected: _relationshipGoal == option,
                onSelected: (selected) {
                  setState(() => _relationshipGoal = selected ? option : null);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.discoveryFiltersHint, style: theme.textTheme.bodySmall),
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

/// Section label with the current value right-aligned, so the slider's state
/// reads without dragging it.
class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.label, {this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
        if (value != null)
          Text(
            value!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }
}
