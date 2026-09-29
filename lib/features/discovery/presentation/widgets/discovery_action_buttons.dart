import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_shadows.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// Pass · Priority intro · Connect.
///
/// Deliberately not a traffic light: pass is a neutral white disc, connect is
/// the one ember disc, and the priority intro sits between them, smaller.
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
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final primary = compact ? 60.0 : 64.0;
        final secondary = compact ? 48.0 : 52.0;
        final gap = compact ? 20.0 : 28.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionDisc(
              icon: MevoraIcons.pass,
              size: primary,
              background: p.surface,
              foreground: p.textPrimary,
              bordered: true,
              label: l10n.pass,
              onPressed: enabled ? onPass : null,
            ),
            SizedBox(width: gap),
            _ActionDisc(
              icon: MevoraIcons.superLike,
              size: secondary,
              background: p.surface,
              foreground: p.humor,
              bordered: true,
              label: l10n.discoveryActionPriorityIntro,
              onPressed: enabled ? onSuperLike : null,
            ),
            SizedBox(width: gap),
            _ActionDisc(
              icon: MevoraIcons.liked,
              size: primary,
              background: scheme.primary,
              foreground: scheme.onPrimary,
              label: l10n.discoveryActionConnect,
              onPressed: enabled ? onLike : null,
            ),
          ],
        );
      },
    );
  }
}

class _ActionDisc extends StatelessWidget {
  const _ActionDisc({
    required this.icon,
    required this.size,
    required this.background,
    required this.foreground,
    required this.label,
    required this.onPressed,
    this.bordered = false,
  });

  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;
  final String label;
  final VoidCallback? onPressed;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: AnimatedOpacity(
          duration: AppDurations.fast,
          opacity: enabled ? 1 : 0.45,
          child: MevoraPressScale(
            enabled: enabled,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: AppShadows.floating(Theme.of(context).brightness),
              ),
              child: Material(
                color: background,
                shape: CircleBorder(
                  side: bordered
                      ? BorderSide(color: context.palette.border)
                      : BorderSide.none,
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  child: SizedBox.square(
                    dimension: size,
                    child: Icon(icon, color: foreground, size: size * 0.42),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
