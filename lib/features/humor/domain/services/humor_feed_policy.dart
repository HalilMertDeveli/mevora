import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';

/// Client-side feed paging and profile-progress helpers.
///
/// There is no item count here: how many items the initial calibration and a
/// day's tour have is the server's to say.
abstract final class HumorFeedPolicy {
  static const int pageSize = 12;
  static const int preloadAhead = 3;

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

  /// How far the initial calibration is, as the server reported it.
  static double buildingProgress(UserHumorProfile profile) {
    if (!profile.profileBuilding) {
      return 1;
    }
    final calibration = profile.calibration;
    if (calibration.totalCount <= 0) {
      return 0;
    }
    return calibration.progress;
  }
}
