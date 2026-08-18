import 'package:mevora/core/config/feature_flags.dart';

/// Remote Config keys. These are product switches, never security controls.
/// Firestore rules and Cloud Functions stay authoritative.
abstract final class RemoteConfigKeys {
  static const String minimumAge = 'minimumAge';
  static const String maxDiscoveryDistance = 'maxDiscoveryDistance';
  static const String maxDailyLikes = 'maxDailyLikes';
  static const String videoCallEnabled = 'videoCallEnabled';
  static const String premiumEnabled = 'premiumEnabled';
  static const String maintenanceMode = 'maintenanceMode';
}

class MevoraRemoteConfig {
  const MevoraRemoteConfig({
    this.minimumAge = 18,
    this.maxDiscoveryDistance = 100,
    this.maxDailyLikes = 100,
    this.videoCallEnabled = false,
    this.premiumEnabled = false,
    this.maintenanceMode = false,
  });

  final int minimumAge;
  final int maxDiscoveryDistance;
  final int maxDailyLikes;
  final bool videoCallEnabled;
  final bool premiumEnabled;
  final bool maintenanceMode;

  static const MevoraRemoteConfig defaults = MevoraRemoteConfig();

  FeatureFlags toFeatureFlags(FeatureFlags current) {
    return current.copyWith(
      minimumAge: minimumAge,
      maxDiscoveryDistanceKm: maxDiscoveryDistance,
      maxDailyLikes: maxDailyLikes,
      videoCallsEnabled: videoCallEnabled,
      premiumEnabled: premiumEnabled,
      maintenanceMode: maintenanceMode,
    );
  }
}

abstract class RemoteConfigDataSource {
  Future<MevoraRemoteConfig> fetch();
}

class DefaultRemoteConfigDataSource implements RemoteConfigDataSource {
  const DefaultRemoteConfigDataSource();

  @override
  Future<MevoraRemoteConfig> fetch() async => MevoraRemoteConfig.defaults;
}
