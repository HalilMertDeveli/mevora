import 'package:flutter/material.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_intro_view.dart';

/// Compact progress strip shown while the humor profile is still learning.
class HumorLearningProgressBanner extends StatelessWidget {
  const HumorLearningProgressBanner({
    super.key,
    required this.profile,
  });

  final UserHumorProfile profile;

  @override
  Widget build(BuildContext context) {
    if (!profile.profileBuilding &&
        profile.interactionCount >= HumorFeedPolicy.buildingThreshold) {
      return const SizedBox.shrink();
    }
    return HumorProgressBlock(interactionCount: profile.interactionCount);
  }
}
