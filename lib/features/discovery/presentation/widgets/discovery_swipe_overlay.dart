import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';

/// Directional stamp shown while dragging or exiting a discovery card.
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

    final l10n = AppLocalizations.of(context);
    final progress = _progressFor(direction);
    final label = switch (direction) {
      DiscoverySwipeDirection.like => l10n.like.toUpperCase(),
      DiscoverySwipeDirection.pass => l10n.pass.toUpperCase(),
      DiscoverySwipeDirection.superLike => l10n.superLike.toUpperCase(),
      DiscoverySwipeDirection.none => '',
    };

    final color = switch (direction) {
      DiscoverySwipeDirection.like => AppColors.moss,
      DiscoverySwipeDirection.pass => AppColors.danger,
      DiscoverySwipeDirection.superLike => AppColors.apricot,
      DiscoverySwipeDirection.none => AppColors.mutedInk,
    };

    final icon = switch (direction) {
      DiscoverySwipeDirection.like => Icons.favorite_rounded,
      DiscoverySwipeDirection.pass => Icons.close_rounded,
      DiscoverySwipeDirection.superLike => Icons.star_rounded,
      DiscoverySwipeDirection.none => Icons.circle_outlined,
    };

    final alignment = switch (direction) {
      DiscoverySwipeDirection.like => Alignment.topLeft,
      DiscoverySwipeDirection.pass => Alignment.topRight,
      DiscoverySwipeDirection.superLike => Alignment.topCenter,
      DiscoverySwipeDirection.none => Alignment.center,
    };

    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Opacity(
            opacity: (0.4 + progress * 0.6).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: switch (direction) {
                DiscoverySwipeDirection.like => -0.18,
                DiscoverySwipeDirection.pass => 0.18,
                DiscoverySwipeDirection.superLike => 0,
                DiscoverySwipeDirection.none => 0,
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: color, width: 3),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                      ),
                    ],
                  ),
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
