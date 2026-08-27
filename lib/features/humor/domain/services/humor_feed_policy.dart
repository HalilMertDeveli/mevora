import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';

/// Client-side feed / profile thresholds aligned with Cloud Functions.
abstract final class HumorFeedPolicy {
  static const int pageSize = 12;
  static const int preloadAhead = 3;
  static const int buildingThreshold = 15;

  static bool isBuilding(int interactionCount) =>
      interactionCount < buildingThreshold;

  static bool shouldPrefetch({
    required int currentIndex,
    required int itemCount,
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    if (!hasMore || isLoadingMore || itemCount == 0) {
      return false;
    }
    return currentIndex >= itemCount - preloadAhead;
  }

  static double buildingProgress(UserHumorProfile profile) {
    if (!profile.profileBuilding) {
      return 1;
    }
    return (profile.interactionCount / buildingThreshold).clamp(0.0, 1.0);
  }
}
