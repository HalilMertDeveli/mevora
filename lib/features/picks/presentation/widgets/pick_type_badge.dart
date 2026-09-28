import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/copy/pick_copy.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// The Pick category as a compact pill. [onMedia] draws it for a photo
/// background; otherwise it sits on the surface.
class PickTypeBadge extends StatelessWidget {
  const PickTypeBadge({
    super.key,
    required this.type,
    this.onMedia = false,
    this.emphasized = true,
  });

  final PickType type;
  final bool onMedia;

  /// The primary reason is emphasised; secondary labels are quieter.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final background = onMedia
        ? Colors.black.withValues(alpha: 0.46)
        : emphasized
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = onMedia
        ? Colors.white
        : emphasized
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PickCopy.typeIcon(type), size: 15, color: foreground),
            const SizedBox(width: AppSpacing.xs + 2),
            Flexible(
              child: Text(
                PickCopy.typeLabel(l10n, type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
