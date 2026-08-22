import 'package:flutter/material.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_swipe_overlay.dart';
import 'package:mevora/shared/animations/mevora_discovery_card_motion.dart';
import 'package:mevora/shared/animations/mevora_like_burst.dart';

/// Discovery swipe that paints only the front card.
///
/// Extra candidates may be passed for photo prefetch, but they are not drawn
/// behind the current person.
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

    final front = candidates.first;

    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onHorizontalDragUpdate: (details) => onDragUpdate(details.delta),
          onVerticalDragUpdate: (details) => onDragUpdate(details.delta),
          onHorizontalDragEnd: (_) => onDragEnd(),
          onVerticalDragEnd: (_) => onDragEnd(),
          child: MevoraDiscoveryCardMotion(
            dragOffset: dragOffset,
            direction: swipeDirection,
            animateOut: animateOut,
            child: DiscoveryProfileCard(
              candidate: front,
              onTap: () => onCardTap(front),
            ),
          ),
        ),
        DiscoverySwipeOverlay(
          dragOffset: dragOffset,
          threshold: swipeThreshold,
        ),
        MevoraLikeBurst(play: showLikeBurst),
      ],
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
