import 'package:flutter/material.dart';
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

  static const _passColor = Color(0xFFFF4458);
  static const _superLikeColor = Color(0xFF1EA7FD);
  static const _likeColor = Color(0xFF2BD68A);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final primarySize = compact ? 56.0 : 64.0;
        final secondarySize = compact ? 44.0 : 50.0;
        final spacing = compact ? 20.0 : 28.0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundActionButton(
              icon: Icons.close_rounded,
              color: _passColor,
              size: primarySize,
              label: l10n.pass,
              onPressed: enabled ? onPass : null,
            ),
            SizedBox(width: spacing),
            _RoundActionButton(
              icon: Icons.star_rounded,
              color: _superLikeColor,
              size: secondarySize,
              label: l10n.discoveryActionPriorityIntro,
              onPressed: enabled ? onSuperLike : null,
            ),
            SizedBox(width: spacing),
            _RoundActionButton(
              icon: Icons.favorite_rounded,
              color: _likeColor,
              size: primarySize,
              label: l10n.discoveryActionConnect,
              onPressed: enabled ? onLike : null,
            ),
          ],
        );
      },
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final double size;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final enabled = onPressed != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.4,
          child: Material(
            color: surface,
            shape: const CircleBorder(),
            elevation: 4,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon, color: color, size: size * 0.52),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
