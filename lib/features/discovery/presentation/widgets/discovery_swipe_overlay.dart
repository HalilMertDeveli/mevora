import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';

/// Directional hint while dragging a card: an icon-only disc in the corner
/// the card is heading toward, growing with the drag. Same vocabulary as the
/// action buttons — ember for connect, ink for pass, marigold for priority —
/// and deliberately wordless so it never covers the person.
class DiscoverySwipeOverlay extends StatelessWidget {
  const DiscoverySwipeOverlay({
    super.key,
    required this.dragOffset,
    this.threshold = 120,
  });

  final Offset dragOffset;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final direction = _resolveDirection();
    if (direction == DiscoverySwipeDirection.none) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final progress = _progressFor(direction);
    final (
      IconData icon,
      Color bg,
      Color fg,
      Alignment at,
    ) = switch (direction) {
      DiscoverySwipeDirection.like => (
        MevoraIcons.liked,
        scheme.primary,
        scheme.onPrimary,
        Alignment.topLeft,
      ),
      DiscoverySwipeDirection.pass => (
        MevoraIcons.pass,
        p.textPrimary,
        p.background,
        Alignment.topRight,
      ),
      _ => (
        MevoraIcons.superLike,
        p.humor,
        AppColors.paper,
        Alignment.topCenter,
      ),
    };

    return IgnorePointer(
      child: Align(
        alignment: at,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Opacity(
            opacity: progress.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + progress * 0.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Icon(icon, color: fg, size: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DiscoverySwipeDirection _resolveDirection() {
    final dx = dragOffset.dx;
    final dy = dragOffset.dy;
    if (dy < -threshold * 0.55 && dy.abs() > dx.abs()) {
      return DiscoverySwipeDirection.superLike;
    }
    if (dx > threshold * 0.35) return DiscoverySwipeDirection.like;
    if (dx < -threshold * 0.35) return DiscoverySwipeDirection.pass;
    return DiscoverySwipeDirection.none;
  }

  double _progressFor(DiscoverySwipeDirection direction) {
    return switch (direction) {
      DiscoverySwipeDirection.like => (dragOffset.dx / threshold).clamp(0, 1),
      DiscoverySwipeDirection.pass => (-dragOffset.dx / threshold).clamp(0, 1),
      DiscoverySwipeDirection.superLike => (-dragOffset.dy / threshold).clamp(
        0,
        1,
      ),
      DiscoverySwipeDirection.none => 0,
    };
  }
}
