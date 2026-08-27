import 'package:flutter/widgets.dart';

/// Humor Lab ad lifecycle. Ads are never counted as humor ratings.
enum HumorAdPhase {
  idle,
  eligible,
  loading,
  shown,
  completed,
  failed,
}

class HumorAdRequest {
  const HumorAdRequest({
    required this.placementId,
    this.isPremium = false,
  });

  final String placementId;
  final bool isPremium;
}

class HumorAdResult {
  const HumorAdResult({
    required this.completed,
    this.failed = false,
    this.errorCode,
  });

  final bool completed;
  final bool failed;
  final String? errorCode;

  static const completedOk = HumorAdResult(completed: true);
  static const failedSoft = HumorAdResult(completed: false, failed: true);
}

/// Port for Humor Lab interstitial / sponsored breaks.
/// UI must not depend on a specific ad SDK.
abstract class HumorAdService {
  /// Whether this service can show ads for free users.
  bool get isAvailable;

  /// Show ad and resolve when the user may resume the feed.
  /// Must not hang forever — soft-fail after timeout / missing host.
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  });
}

/// Premium / disabled path — never shows ads.
class NoopHumorAdService implements HumorAdService {
  const NoopHumorAdService();

  @override
  bool get isAvailable => false;

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    return HumorAdResult.completedOk;
  }
}
