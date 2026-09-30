import 'package:flutter/foundation.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed version from the platform, via package_info_plus.
class PackageInfoAppVersionProvider implements AppVersionProvider {
  const PackageInfoAppVersionProvider();

  @override
  Future<InstalledApp> installed() async {
    final platform = currentAppPlatform();
    try {
      final info = await PackageInfo.fromPlatform();
      return InstalledApp(platform: platform, version: info.version);
    } on Object {
      // Unknown version gates nothing.
      return InstalledApp(platform: platform, version: null);
    }
  }
}

AppPlatform currentAppPlatform() {
  if (kIsWeb) {
    return AppPlatform.other;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.iOS => AppPlatform.ios,
    _ => AppPlatform.other,
  };
}
