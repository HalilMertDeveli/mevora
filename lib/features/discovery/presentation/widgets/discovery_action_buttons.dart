import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/l10n/app_localizations.dart';

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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionCircle(
          icon: Icons.close_rounded,
          color: AppColors.danger,
          tooltip: l10n.pass,
          onPressed: enabled ? onPass : null,
          size: 56,
        ),
        const SizedBox(width: AppSpacing.lg),
        _ActionCircle(
          icon: Icons.star_rounded,
          color: AppColors.apricot,
          tooltip: l10n.superLike,
          onPressed: enabled ? onSuperLike : null,
          size: 64,
        ),
        const SizedBox(width: AppSpacing.lg),
        _ActionCircle(
          icon: Icons.favorite_rounded,
          color: AppColors.moss,
          tooltip: l10n.like,
          onPressed: enabled ? onLike : null,
          size: 56,
        ),
      ],
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: onPressed == null ? 0 : 2,
        shadowColor: color.withValues(alpha: 0.25),
        shape: CircleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: onPressed == null ? theme.disabledColor : color,
              size: size * 0.42,
            ),
          ),
        ),
      ),
    );
  }
}
