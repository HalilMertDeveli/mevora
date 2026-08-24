import 'package:flutter/material.dart';
import 'package:mevora/features/profile/domain/catalog/height_catalog.dart';
import 'package:mevora/l10n/app_localizations.dart';

class ProfileHeightPicker extends StatelessWidget {
  const ProfileHeightPicker({
    super.key,
    required this.valueCm,
    required this.onChanged,
    this.enabled = true,
  });

  final int? valueCm;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = HeightCatalog.options;

    final selectedIndex = valueCm == null
        ? 0
        : () {
            final idx = options.indexWhere((cm) => cm == valueCm);
            if (idx < 0) return 0;
            if (idx >= options.length) return options.length - 1;
            return idx;
          }();

    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge;

    return SizedBox(
      height: 160,
      child: ListWheelScrollView.useDelegate(
        key: ValueKey(valueCm),
        controller: FixedExtentScrollController(initialItem: selectedIndex),
        itemExtent: 40,
        physics: enabled
            ? const FixedExtentScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onSelectedItemChanged: enabled
            ? (index) => onChanged(options[index])
            : null,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: options.length,
          builder: (context, index) {
            final cm = options[index];
            final label = l10n.profileHeightCm(cm);
            final isSelected = valueCm == cm;
            return Center(
              child: Text(
                label,
                style: textStyle?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
