import 'package:flutter/material.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';

/// Subtle directional hint while dragging a discovery card: a round icon
/// that fades in and grows with the drag, matching the action buttons.
class DiscoverySwipeOverlay extends StatelessWidget {
  const DiscoverySwipeOverlay({
    super.key,
    required this.dragOffset,
    this.threshold = 120,
  });

  final Offset dragOffset;
  final double threshold;

  static const _passColor = Color(0xFFFF4458);
  static const _superLikeColor = Color(0xFF1EA7FD);
  static const _likeColor = Color(0xFF2BD68A);

  @override
  Widget build(BuildContext context) {
    final direction = _resolveDirection();
    if (direction == DiscoverySwipeDirection.none) {
      return const SizedBox.shrink();
    }

    final progress = _progressFor(direction);
    final (icon, color) = switch (direction) {
      DiscoverySwipeDirection.like => (Icons.favorite_rounded, _likeColor),
      DiscoverySwipeDirection.pass => (Icons.close_rounded, _passColor),
      DiscoverySwipeDirection.superLike => (
        Icons.star_rounded,
        _superLikeColor,
      ),
      DiscoverySwipeDirection.none => (Icons.circle, Colors.transparent),
    };

    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: (0.2 + progress * 0.8).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + progress * 0.3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(icon, color: color, size: 56),
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
    if (dx > threshold * 0.35) {
      return DiscoverySwipeDirection.like;
    }
    if (dx < -threshold * 0.35) {
      return DiscoverySwipeDirection.pass;
    }
    return DiscoverySwipeDirection.none;
  }

  double _progressFor(DiscoverySwipeDirection direction) {
    return switch (direction) {
      DiscoverySwipeDirection.like => (dragOffset.dx / threshold).clamp(
        0.0,
        1.0,
      ),
      DiscoverySwipeDirection.pass => (-dragOffset.dx / threshold).clamp(
        0.0,
        1.0,
      ),
      DiscoverySwipeDirection.superLike => (-dragOffset.dy / threshold).clamp(
        0.0,
        1.0,
      ),
      DiscoverySwipeDirection.none => 0,
    };
  }
}
