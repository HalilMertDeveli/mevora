import 'package:flutter/material.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_swipe_overlay.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';
import 'package:mevora/shared/animations/mevora_like_burst.dart';

/// Three-card discovery stack with drag handling on the front card only.
class DiscoveryCardStack extends StatelessWidget {
  const DiscoveryCardStack({
    super.key,
    required this.candidates,
    required this.dragOffset,
    required this.swipeDirection,
    required this.animateOut,
    required this.showLikeBurst,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onCardTap,
    this.swipeThreshold = 120,
  });

  final List<DiscoveryCandidate> candidates;
  final Offset dragOffset;
  final DiscoverySwipeDirection swipeDirection;
  final bool animateOut;
  final bool showLikeBurst;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<DiscoveryCandidate> onCardTap;
  final double swipeThreshold;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        for (var index = candidates.length - 1; index >= 0; index--)
          _StackedCard(
            candidate: candidates[index],
            depth: candidates.length - 1 - index,
            isFront: index == 0,
            dragOffset: index == 0 ? dragOffset : Offset.zero,
            swipeDirection: index == 0 ? swipeDirection : DiscoverySwipeDirection.none,
            animateOut: index == 0 && animateOut,
            onDragUpdate: index == 0 ? onDragUpdate : null,
            onDragEnd: index == 0 ? onDragEnd : null,
            onTap: () => onCardTap(candidates[index]),
            swipeThreshold: swipeThreshold,
          ),
        if (candidates.isNotEmpty)
          DiscoverySwipeOverlay(
            dragOffset: dragOffset,
            threshold: swipeThreshold,
          ),
        MevoraLikeBurst(play: showLikeBurst),
      ],
    );
  }
}

class _StackedCard extends StatelessWidget {
  const _StackedCard({
    required this.candidate,
    required this.depth,
    required this.isFront,
    required this.dragOffset,
    required this.swipeDirection,
    required this.animateOut,
    required this.onTap,
    this.onDragUpdate,
    this.onDragEnd,
    required this.swipeThreshold,
  });

  final DiscoveryCandidate candidate;
  final int depth;
  final bool isFront;
  final Offset dragOffset;
  final DiscoverySwipeDirection swipeDirection;
  final bool animateOut;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback onTap;
  final double swipeThreshold;

  @override
  Widget build(BuildContext context) {
    final scale = 1 - (depth * 0.04);
    final yOffset = depth * 10.0;
    final opacity = 1 - (depth * 0.12);

    Widget card = MevoraDiscoveryCardMotion(
      dragOffset: dragOffset,
      direction: swipeDirection,
      animateOut: animateOut,
      child: DiscoveryProfileCard(candidate: candidate, onTap: onTap),
    );

    if (isFront && onDragUpdate != null && onDragEnd != null) {
      card = GestureDetector(
        onHorizontalDragUpdate: (details) => onDragUpdate!(details.delta),
        onVerticalDragUpdate: (details) => onDragUpdate!(details.delta),
        onHorizontalDragEnd: (_) => onDragEnd!(),
        onVerticalDragEnd: (_) => onDragEnd!(),
        child: card,
      );
    }

    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: card,
        ),
      ),
    );
  }
}

/// Prefetches the next card photo without blocking swipe gestures.
void prefetchDiscoveryPhotos(List<DiscoveryCandidate> candidates) {
  for (final candidate in candidates.take(2)) {
    for (final url in candidate.photos.take(1)) {
      DiscoveryNetworkImage.prefetch(url);
    }
  }
}
