import 'package:flutter/material.dart';
import 'package:mevora/features/profile/domain/catalog/height_catalog.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Wheel height picker (140–220 cm).
///
/// Keeps a single [FixedExtentScrollController] across rebuilds so flings are
/// not cancelled by remounting the wheel on every centimetre change.
class ProfileHeightPicker extends StatefulWidget {
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
  State<ProfileHeightPicker> createState() => _ProfileHeightPickerState();
}

class _ProfileHeightPickerState extends State<ProfileHeightPicker> {
  late final FixedExtentScrollController _controller;
  var _suppressNotify = false;

  static int _indexFor(int? valueCm) {
    final options = HeightCatalog.options;
    if (valueCm == null) {
      return 0;
    }
    final idx = options.indexWhere((cm) => cm == valueCm);
    if (idx < 0) {
      return 0;
    }
    if (idx >= options.length) {
      return options.length - 1;
    }
    return idx;
  }

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: _indexFor(widget.valueCm),
    );
  }

  @override
  void didUpdateWidget(covariant ProfileHeightPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueCm == widget.valueCm) {
      return;
    }
    final next = _indexFor(widget.valueCm);
    if (!_controller.hasClients || _controller.selectedItem == next) {
      return;
    }
    // External value change (e.g. draft reload) — snap without fighting a fling
    // that already called [onChanged].
    _suppressNotify = true;
    _controller.jumpToItem(next);
    _suppressNotify = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = HeightCatalog.options;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge;

    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: SizedBox(
        height: 160,
        child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: 36,
          diameterRatio: 1.35,
          perspective: 0.003,
          physics: widget.enabled
              ? const FixedExtentScrollPhysics(
                  parent: BouncingScrollPhysics(
                    decelerationRate: ScrollDecelerationRate.fast,
                  ),
                )
              : const NeverScrollableScrollPhysics(),
          onSelectedItemChanged: widget.enabled
              ? (index) {
                  if (_suppressNotify) {
                    return;
                  }
                  widget.onChanged(options[index]);
                }
              : null,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: options.length,
            builder: (context, index) {
              final cm = options[index];
              final label = l10n.profileHeightCm(cm);
              final isSelected = widget.valueCm == cm;
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
      ),
    );
  }
}
