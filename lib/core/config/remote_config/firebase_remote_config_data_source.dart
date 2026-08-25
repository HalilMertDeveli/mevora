import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/remote_config/mevora_remote_config.dart';

/// Fetches Firebase Remote Config with safe defaults on failure.
/// Product switches only — never a security control.
class FirebaseRemoteConfigDataSource implements RemoteConfigDataSource {
  const FirebaseRemoteConfigDataSource();

  @override
  Future<MevoraRemoteConfig> fetch() async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    try {
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 1),
        ),
      );
      await remoteConfig.setDefaults(<String, dynamic>{
        RemoteConfigKeys.minimumAge: MevoraRemoteConfig.defaults.minimumAge,
        RemoteConfigKeys.maxDiscoveryDistance:
            MevoraRemoteConfig.defaults.maxDiscoveryDistance,
        RemoteConfigKeys.maxDailyLikes: MevoraRemoteConfig.defaults.maxDailyLikes,
        RemoteConfigKeys.videoCallEnabled:
            MevoraRemoteConfig.defaults.videoCallEnabled,
        RemoteConfigKeys.premiumEnabled:
            MevoraRemoteConfig.defaults.premiumEnabled,
        RemoteConfigKeys.maintenanceMode:
            MevoraRemoteConfig.defaults.maintenanceMode,
        RemoteConfigKeys.boostCatalogJson:
            MevoraRemoteConfig.defaults.boostCatalogJson,
      });
      await remoteConfig.fetchAndActivate();
      return MevoraRemoteConfig(
        minimumAge: remoteConfig.getInt(RemoteConfigKeys.minimumAge),
        maxDiscoveryDistance: remoteConfig.getInt(
          RemoteConfigKeys.maxDiscoveryDistance,
        ),
        maxDailyLikes: remoteConfig.getInt(RemoteConfigKeys.maxDailyLikes),
        videoCallEnabled: remoteConfig.getBool(
          RemoteConfigKeys.videoCallEnabled,
        ),
        premiumEnabled: remoteConfig.getBool(RemoteConfigKeys.premiumEnabled),
        maintenanceMode: remoteConfig.getBool(
          RemoteConfigKeys.maintenanceMode,
        ),
        boostCatalogJson: remoteConfig.getString(
          RemoteConfigKeys.boostCatalogJson,
        ),
      );
    } on Object {
      return MevoraRemoteConfig.defaults;
    }
  }
}
