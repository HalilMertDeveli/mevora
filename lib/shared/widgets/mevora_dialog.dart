import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

abstract final class MevoraDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = AppStrings.confirm,
    String cancelLabel = AppStrings.cancel,
    bool showCancel = true,
    bool barrierDismissible = true,
    MevoraButtonVariant confirmVariant = MevoraButtonVariant.primary,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          actions: [
            if (showCancel)
              MevoraButton(
                label: cancelLabel,
                variant: MevoraButtonVariant.ghost,
                isExpanded: false,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
            MevoraButton(
              label: confirmLabel,
              variant: confirmVariant,
              isExpanded: false,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
  }
}
