import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileMultiSelectPicker extends StatelessWidget {
  const ProfileMultiSelectPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.labelFor,
    this.enabled = true,
    this.minSelection = 0,
    this.maxSelection = 99,
    this.hint,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String Function(String id) labelFor;
  final bool enabled;
  final int minSelection;
  final int maxSelection;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hint != null) ...[
          Text(hint!),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in options)
              MevoraChip(
                label: labelFor(option),
                selected: selected.contains(option),
                onSelected: enabled
                    ? (value) {
                        final next = {...selected};
                        if (value) {
                          if (next.length >= maxSelection) {
                            return;
                          }
                          next.add(option);
                        } else if (next.length > minSelection || minSelection == 0) {
                          next.remove(option);
                        } else {
                          return;
                        }
                        onChanged(next);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
