import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/profile/domain/catalog/height_catalog.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

/// Height (140–220 cm) as a tappable field that opens a wheel in a sheet.
///
/// The wheel used to sit inline in the scrolling pages that host this field.
/// It owns the vertical drag, so a thumb scrolling the page across it changed
/// the height instead — silently. Inline there is now only a field, which lets
/// a drag through to the page; the wheel lives in a modal sheet and nothing is
/// reported until the member confirms.
class ProfileHeightPicker extends StatefulWidget {
  const ProfileHeightPicker({
    super.key,
    required this.valueCm,
    required this.onChanged,
    this.enabled = true,
  });

  /// Null while the member has not set a height.
  final int? valueCm;

  /// Called once per confirmed sheet, with the confirmed height.
  final ValueChanged<int?> onChanged;
  final bool enabled;

  @override
  State<ProfileHeightPicker> createState() => _ProfileHeightPickerState();
}

class _ProfileHeightPickerState extends State<ProfileHeightPicker> {
  /// Where the wheel opens for a member with no height yet. Nothing is
  /// stored until they confirm.
  static const _unsetStartCm = 170;

  final _valueController = TextEditingController();
  var _sheetOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncValueText();
  }

  @override
  void didUpdateWidget(covariant ProfileHeightPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueCm != widget.valueCm) {
      _syncValueText();
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _syncValueText() {
    final cm = widget.valueCm;
    final text = cm == null
        ? ''
        : AppLocalizations.of(context).profileHeightCm(cm);
    if (_valueController.text != text) {
      _valueController.text = text;
    }
  }

  Future<void> _openSheet() async {
    if (_sheetOpen) {
      return;
    }
    _sheetOpen = true;
    final start = (widget.valueCm ?? _unsetStartCm).clamp(
      HeightCatalog.minCm,
      HeightCatalog.maxCm,
    );
    final confirmed = await MevoraBottomSheet.show<int>(
      context,
      title: AppLocalizations.of(context).profileHeightLabel,
      child: _HeightWheel(initialCm: start),
    );
    _sheetOpen = false;
    if (confirmed == null || !mounted) {
      return;
    }
    widget.onChanged(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cm = widget.valueCm;
    final shown = cm == null
        ? l10n.profileHeightPlaceholder
        : l10n.profileHeightCm(cm);
    final onTap = widget.enabled ? () => unawaited(_openSheet()) : null;

    // One node for assistive technology: what the field is, what it holds,
    // and that it opens something — rather than a read-only text field.
    return Semantics(
      container: true,
      button: true,
      enabled: widget.enabled,
      label: '${l10n.profileHeightLabel}, $shown',
      onTap: onTap,
      excludeSemantics: true,
      child: MevoraTextField(
        controller: _valueController,
        hint: l10n.profileHeightPlaceholder,
        readOnly: true,
        enabled: widget.enabled,
        suffixIcon: const Icon(MevoraIcons.dropdown),
        onTap: onTap,
      ),
    );
  }
}

/// The wheel and its confirm button. Pops with the confirmed height; any
/// other way out of the sheet pops with nothing.
class _HeightWheel extends StatefulWidget {
  const _HeightWheel({required this.initialCm});

  final int initialCm;

  @override
  State<_HeightWheel> createState() => _HeightWheelState();
}

class _HeightWheelState extends State<_HeightWheel> {
  static final List<int> _options = HeightCatalog.options;
  static const _visibleRows = 5;

  late final FixedExtentScrollController _controller;
  late int _selectedCm = widget.initialCm;

  @override
  void initState() {
    super.initState();
    final index = _options.indexOf(widget.initialCm);
    _controller = FixedExtentScrollController(
      initialItem: index < 0 ? 0 : index,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge;
    // Rows grow with the member's text size so a label is never clipped.
    final itemExtent = MediaQuery.textScalerOf(
      context,
    ).scale(36).clamp(36.0, 64.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A band marks the row that counts, so the wheel reads as a picker
        // rather than as a floating list.
        SizedBox(
          height: itemExtent * _visibleRows,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: Container(
                  height: itemExtent + 4,
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: context.palette.border),
                  ),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: itemExtent,
                diameterRatio: 1.35,
                perspective: 0.003,
                physics: const FixedExtentScrollPhysics(
                  parent: BouncingScrollPhysics(
                    decelerationRate: ScrollDecelerationRate.fast,
                  ),
                ),
                onSelectedItemChanged: (index) =>
                    setState(() => _selectedCm = _options[index]),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: _options.length,
                  builder: (context, index) {
                    final cm = _options[index];
                    final isSelected = _selectedCm == cm;
                    return Center(
                      child: Text(
                        l10n.profileHeightCm(cm),
                        style: textStyle?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        MevoraButton(
          label: l10n.done,
          onPressed: () => Navigator.of(context).pop(_selectedCm),
        ),
      ],
    );
  }
}
