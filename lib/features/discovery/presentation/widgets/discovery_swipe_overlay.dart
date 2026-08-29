import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';

/// Subtle directional hint while dragging a discovery card.
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
      DiscoverySwipeDirection.like => l10n.discoveryActionConnect,
      DiscoverySwipeDirection.pass => l10n.pass,
      DiscoverySwipeDirection.superLike => l10n.discoveryActionPriorityIntro,
      DiscoverySwipeDirection.none => '',
    };

    final color = switch (direction) {
      DiscoverySwipeDirection.like => AppColors.amber,
      DiscoverySwipeDirection.pass => AppColors.error,
      DiscoverySwipeDirection.superLike => AppColors.midnight,
      DiscoverySwipeDirection.none => AppColors.mutedInk,
    };

    final alignment = switch (direction) {
      DiscoverySwipeDirection.like => Alignment.bottomCenter,
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
            opacity: (0.25 + progress * 0.55).clamp(0.0, 0.8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
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
