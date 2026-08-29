import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class DiscoveryActionButtons extends StatelessWidget {
  const DiscoveryActionButtons({
    super.key,
    required this.onPass,
    required this.onSuperLike,
    required this.onLike,
    this.enabled = true,
  });

  final VoidCallback onPass;
  final VoidCallback onSuperLike;
  final VoidCallback onLike;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 400 || textScale > 1.15;
        final size =
            compact ? MevoraButtonSize.small : MevoraButtonSize.medium;
        final connectFlex = compact ? 1 : 2;
        final spacing = compact ? AppSpacing.xs : AppSpacing.sm;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MevoraButton(
                label: l10n.pass,
                variant: MevoraButtonVariant.secondary,
                size: size,
                wrapLabel: compact,
                onPressed: enabled ? onPass : null,
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: MevoraButton(
                label: l10n.discoveryActionPriorityIntro,
                variant: MevoraButtonVariant.ghost,
                size: size,
                wrapLabel: compact,
                onPressed: enabled ? onSuperLike : null,
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              flex: connectFlex,
              child: MevoraButton(
                label: l10n.discoveryActionConnect,
                size: size,
                wrapLabel: compact,
                onPressed: enabled ? onLike : null,
              ),
            ),
          ],
        );
      },
    );
  }
}
