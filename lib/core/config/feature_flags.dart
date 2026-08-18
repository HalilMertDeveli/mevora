/// Central feature flags. UI and use cases read these instead of scattering
/// hardcoded `if` checks. Defaults are off until the matching product
/// surface is ready.
class FeatureFlags {
  const FeatureFlags({
    this.videoCallsEnabled = false,
    this.spotifyLoginEnabled = false,
    this.premiumEnabled = false,
    this.aiRecommendationsEnabled = false,
    this.minimumAge = 18,
    this.maxDiscoveryDistanceKm = 100,
    this.maxDailyLikes = 100,
    this.maintenanceMode = false,
  });

  final bool videoCallsEnabled;
  final bool spotifyLoginEnabled;
  final bool premiumEnabled;
  final bool aiRecommendationsEnabled;
  final int minimumAge;
  final int maxDiscoveryDistanceKm;
  final int maxDailyLikes;
  final bool maintenanceMode;

  FeatureFlags copyWith({
    bool? videoCallsEnabled,
    bool? spotifyLoginEnabled,
    bool? premiumEnabled,
    bool? aiRecommendationsEnabled,
    int? minimumAge,
    int? maxDiscoveryDistanceKm,
    int? maxDailyLikes,
    bool? maintenanceMode,
  }) {
    return FeatureFlags(
      videoCallsEnabled: videoCallsEnabled ?? this.videoCallsEnabled,
      spotifyLoginEnabled: spotifyLoginEnabled ?? this.spotifyLoginEnabled,
      premiumEnabled: premiumEnabled ?? this.premiumEnabled,
      aiRecommendationsEnabled:
          aiRecommendationsEnabled ?? this.aiRecommendationsEnabled,
      minimumAge: minimumAge ?? this.minimumAge,
      maxDiscoveryDistanceKm:
          maxDiscoveryDistanceKm ?? this.maxDiscoveryDistanceKm,
      maxDailyLikes: maxDailyLikes ?? this.maxDailyLikes,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
    );
  }
}
