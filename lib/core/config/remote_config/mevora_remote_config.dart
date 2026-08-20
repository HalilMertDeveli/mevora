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
  static const String boostCatalogJson = 'boostCatalogJson';
}

class MevoraRemoteConfig {
  const MevoraRemoteConfig({
    this.minimumAge = 18,
    this.maxDiscoveryDistance = 100,
    this.maxDailyLikes = 100,
    this.videoCallEnabled = false,
    this.premiumEnabled = false,
    this.maintenanceMode = false,
    this.boostCatalogJson = defaultBoostCatalogJson,
  });

  final int minimumAge;
  final int maxDiscoveryDistance;
  final int maxDailyLikes;
  final bool videoCallEnabled;
  final bool premiumEnabled;
  final bool maintenanceMode;

  /// JSON array of Boost packs. Firestore `boostProducts` is authoritative;
  /// this is an offline/default overlay, never a price charged to the user.
  final String boostCatalogJson;

  static const String defaultBoostCatalogJson =
      '['
      '{"productId":"com.mevora.app.boost.1","boostCount":1,"displayOrder":0,"fallbackPriceAmount":49.99,"fallbackCurrency":"TRY","durationMinutes":30},'
      '{"productId":"com.mevora.app.boost.5","boostCount":5,"displayOrder":1,"fallbackPriceAmount":199.99,"fallbackCurrency":"TRY","durationMinutes":30},'
      '{"productId":"com.mevora.app.boost.10","boostCount":10,"displayOrder":2,"fallbackPriceAmount":349.99,"fallbackCurrency":"TRY","durationMinutes":30}'
      ']';

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
