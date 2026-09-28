import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';

/// Mevora's modal sheet: theme drag handle, optional serif title, content
/// padded for the keyboard and the gesture bar.
abstract final class MevoraBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    String? subtitle,
    bool isDismissible = true,
    bool scrollable = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.headlineSmall),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        );
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            bottom:
                MediaQuery.viewInsetsOf(sheetContext).bottom +
                MediaQuery.paddingOf(sheetContext).bottom +
                AppSpacing.md,
          ),
          child: scrollable ? SingleChildScrollView(child: content) : content,
        );
      },
    );
  }

  /// A list of actions (photo source, attach menu, …). Returns the chosen
  /// value, or null when dismissed.
  static Future<T?> showActions<T>(
    BuildContext context, {
    required List<MevoraSheetAction<T>> actions,
    String? title,
  }) {
    return show<T>(
      context,
      title: title,
      child: Builder(
        builder: (sheetContext) => MevoraListGroup(
          children: [
            for (final action in actions)
              MevoraListRow(
                title: action.label,
                icon: action.icon,
                destructive: action.destructive,
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop(action.value),
              ),
          ],
        ),
      ),
    );
  }
}

class MevoraSheetAction<T> {
  const MevoraSheetAction({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;
}

/// The drag-handle-less header row used inside full-height sheets.
class MevoraSheetHandle extends StatelessWidget {
  const MevoraSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        decoration: BoxDecoration(
          color: context.palette.borderStrong,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
