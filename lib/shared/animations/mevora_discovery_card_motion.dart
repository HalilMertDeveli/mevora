import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';

enum DiscoverySwipeDirection { none, like, pass, superLike }

/// Translates, rotates, scales, and fades a discovery card from a drag offset.
class MevoraDiscoveryCardMotion extends StatelessWidget {
  const MevoraDiscoveryCardMotion({
    super.key,
    required this.child,
    this.dragOffset = Offset.zero,
    this.direction = DiscoverySwipeDirection.none,
    this.animateOut = false,
  });

  final Widget child;
  final Offset dragOffset;
  final DiscoverySwipeDirection direction;
  final bool animateOut;

  static const double _maxRotation = 0.12;
  static const double _exitDistance = 420;

  Offset get _resolvedOffset {
    if (!animateOut) {
      return dragOffset;
    }
    return switch (direction) {
      DiscoverySwipeDirection.like => const Offset(_exitDistance, 0),
      DiscoverySwipeDirection.pass => const Offset(-_exitDistance, 0),
      DiscoverySwipeDirection.superLike => const Offset(0, -_exitDistance),
      DiscoverySwipeDirection.none => dragOffset,
    };
  }

  @override
  Widget build(BuildContext context) {
    final offset = _resolvedOffset;
    final progress = (offset.dx.abs() / 240).clamp(0.0, 1.0);
    final rotation = (offset.dx / 480).clamp(-_maxRotation, _maxRotation);
    final scale = 1 - (progress * 0.04);
    final opacity = 1 - (progress * 0.18);
    final angle = rotation * math.pi / 6;
    final isIdentity =
        !animateOut &&
        offset == Offset.zero &&
        angle == 0 &&
        scale == 1 &&
        opacity == 1;

    // Identity transforms still rasterize with FilterQuality.low and soften photos.
    if (isIdentity) {
      return child;
    }

    final content = Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: offset,
        filterQuality: FilterQuality.high,
        child: Transform.rotate(
          angle: angle,
          filterQuality: FilterQuality.high,
          child: Transform.scale(
            scale: scale,
            filterQuality: FilterQuality.high,
            child: child,
          ),
        ),
      ),
    );

    if (!animateOut) {
      return content;
    }

    return AnimatedContainer(
      duration: AppDurations.discoveryCard,
      curve: Curves.easeOutCubic,
      child: content,
    );
  }
}
