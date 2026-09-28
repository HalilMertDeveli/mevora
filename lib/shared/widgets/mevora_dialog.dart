import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Confirmation dialog. Actions stack full-width (primary on top) so long
/// Turkish labels never truncate and the safe choice is always reachable.
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
    MevoraArt? art,
  }) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolvedConfirm = confirmLabel ?? l10n?.confirm ?? 'Confirm';
    final resolvedCancel = cancelLabel ?? l10n?.cancel ?? 'Cancel';
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.s12,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          icon: art == null ? null : MevoraSpot(art: art, size: 80),
          title: Text(
            title,
            style: theme.textTheme.headlineSmall,
            textAlign: art != null ? TextAlign.center : TextAlign.start,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: art != null ? TextAlign.center : TextAlign.start,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  MevoraButton(
                    label: resolvedConfirm,
                    variant: confirmVariant,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                  if (showCancel) ...[
                    const SizedBox(height: AppSpacing.xs),
                    MevoraButton(
                      label: resolvedCancel,
                      variant: MevoraButtonVariant.ghost,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
