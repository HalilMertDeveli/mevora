import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

abstract final class MevoraDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool showCancel = true,
    bool barrierDismissible = true,
    MevoraButtonVariant confirmVariant = MevoraButtonVariant.primary,
  }) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolvedConfirm = confirmLabel ?? l10n?.confirm ?? 'Confirm';
    final resolvedCancel = cancelLabel ?? l10n?.cancel ?? 'Cancel';
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
                label: resolvedCancel,
                variant: MevoraButtonVariant.ghost,
                isExpanded: false,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
            MevoraButton(
              label: resolvedConfirm,
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
