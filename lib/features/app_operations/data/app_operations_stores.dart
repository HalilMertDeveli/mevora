import 'dart:convert';

import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [AppOperationsStore] on [SharedPreferences]. A cache entry that cannot be
/// read is treated as absent, never as a gate.
class SharedPreferencesAppOperationsStore implements AppOperationsStore {
  SharedPreferencesAppOperationsStore(this._preferences);

  static const String configKey = 'appOperations.config.v1';
  static const String dismissedAnnouncementKey =
      'appOperations.dismissedAnnouncementId';
  static const String dismissedRecommendedKey =
      'appOperations.dismissedRecommendedVersion';

  final SharedPreferences _preferences;

  @override
  AppOperationsConfig? readConfig() {
    final raw = _preferences.getString(configKey);
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? AppOperationsConfig.fromMap(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeConfig(AppOperationsConfig config) async {
    await _preferences.setString(configKey, jsonEncode(config.toJson()));
  }

  @override
  String? readDismissedAnnouncementId() =>
      _preferences.getString(dismissedAnnouncementKey);

  @override
  Future<void> writeDismissedAnnouncementId(String id) async {
    await _preferences.setString(dismissedAnnouncementKey, id);
  }

  @override
  String? readDismissedRecommendedVersion() =>
      _preferences.getString(dismissedRecommendedKey);

  @override
  Future<void> writeDismissedRecommendedVersion(String version) async {
    await _preferences.setString(dismissedRecommendedKey, version);
  }
}

/// [AppOperationsStore] kept in memory — tests, and builds without storage.
class MemoryAppOperationsStore implements AppOperationsStore {
  MemoryAppOperationsStore({
    this.config,
    this.dismissedAnnouncementId,
    this.dismissedRecommendedVersion,
  });

  AppOperationsConfig? config;
  String? dismissedAnnouncementId;
  String? dismissedRecommendedVersion;
  int writes = 0;

  @override
  AppOperationsConfig? readConfig() => config;

  @override
  Future<void> writeConfig(AppOperationsConfig config) async {
    this.config = config;
    writes++;
  }

  @override
  String? readDismissedAnnouncementId() => dismissedAnnouncementId;

  @override
  Future<void> writeDismissedAnnouncementId(String id) async {
    dismissedAnnouncementId = id;
  }

  @override
  String? readDismissedRecommendedVersion() => dismissedRecommendedVersion;

  @override
  Future<void> writeDismissedRecommendedVersion(String version) async {
    dismissedRecommendedVersion = version;
  }
}
