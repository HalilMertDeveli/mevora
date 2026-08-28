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
    return Row(
      children: [
        Expanded(
          child: MevoraButton(
            label: l10n.pass,
            variant: MevoraButtonVariant.secondary,
            size: MevoraButtonSize.medium,
            onPressed: enabled ? onPass : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: MevoraButton(
            label: l10n.discoveryActionPriorityIntro,
            variant: MevoraButtonVariant.ghost,
            size: MevoraButtonSize.medium,
            onPressed: enabled ? onSuperLike : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: MevoraButton(
            label: l10n.discoveryActionConnect,
            size: MevoraButtonSize.medium,
            onPressed: enabled ? onLike : null,
          ),
        ),
      ],
    );
  }
}
