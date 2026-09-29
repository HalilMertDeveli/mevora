import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/copy/pick_copy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// The Pick category as a pill in its signal colour. [onMedia] draws it for a
/// photo background; otherwise it is a [MevoraPill].
class PickTypeBadge extends StatelessWidget {
  const PickTypeBadge({
    super.key,
    required this.type,
    this.onMedia = false,
    this.emphasized = true,
  });

  final PickType type;
  final bool onMedia;

  /// The primary reason carries its signal colour; secondary labels are
  /// neutral and denser.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = PickCopy.typeLabel(l10n, type);
    final icon = PickCopy.typeIcon(type);
    if (!onMedia) {
      return MevoraPill(
        label: label,
        icon: icon,
        tone: emphasized ? PickCopy.typeTone(type) : MevoraTone.neutral,
        dense: !emphasized,
      );
    }
    // Over photography: the same translucent control surface MevoraChip uses
    // on media, so it reads on any portrait.
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: AppColors.onMedia);
    return Semantics(
      label: label,
      excludeSemantics: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.mediaControl,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: AppColors.mediaControlBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.xs + 1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.onMedia),
              const SizedBox(width: AppSpacing.xs + 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
