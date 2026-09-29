import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// * [plain] — app bar / toolbar icon.
/// * [tonal] — a soft circle on the page.
/// * [surface] — a white circle with a hairline (floating over content).
/// * [onMedia] — translucent dark circle for use over photography.
/// * [primary] — the filled ember circle (at most one per view).
enum MevoraIconButtonVariant { plain, tonal, surface, onMedia, primary }

/// Circular icon button. A [tooltip] is required: it is the accessible name.
class MevoraIconButton extends StatelessWidget {
  const MevoraIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.variant = MevoraIconButtonVariant.plain,
    this.size = 48,
    this.iconSize,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final MevoraIconButtonVariant variant;
  final double size;
  final double? iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      MevoraIconButtonVariant.plain => (
        Colors.transparent,
        p.textPrimary,
        BorderSide.none,
      ),
      MevoraIconButtonVariant.tonal => (
        p.surfaceMuted,
        p.textPrimary,
        BorderSide.none,
      ),
      MevoraIconButtonVariant.surface => (
        p.surface,
        p.textPrimary,
        BorderSide(color: p.border),
      ),
      MevoraIconButtonVariant.onMedia => (
        AppColors.mediaControl,
        AppColors.onMedia,
        const BorderSide(color: AppColors.mediaControlBorder),
      ),
      MevoraIconButtonVariant.primary => (
        scheme.primary,
        scheme.onPrimary,
        BorderSide.none,
      ),
    };
    final enabled = onPressed != null;
    return MevoraPressScale(
      enabled: enabled && variant != MevoraIconButtonVariant.plain,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: iconSize ?? (size >= 56 ? 26 : 22),
        style: IconButton.styleFrom(
          fixedSize: Size.square(size),
          minimumSize: Size.square(size < 48 ? size : 48),
          backgroundColor: bg,
          foregroundColor: color ?? fg,
          disabledBackgroundColor: bg.withValues(alpha: bg.a * 0.5),
          disabledForegroundColor: p.textTertiary,
          shape: CircleBorder(side: side),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(icon),
      ),
    );
  }
}
