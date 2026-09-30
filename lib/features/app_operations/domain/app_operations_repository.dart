import 'package:mevora/features/app_operations/domain/app_operations_config.dart';

/// The live operations document. Emits [AppOperationsConfig.defaults] when
/// the document does not exist; errors are passed through for the caller to
/// ride out with whatever it last knew.
abstract interface class AppOperationsRepository {
  Stream<AppOperationsConfig> watch();
}

/// Device-local memory for the operations client: the last valid document,
/// so a cold start offline still honours maintenance and update gates, and
/// what the member already dismissed.
///
/// Reads are synchronous so the first frame can already be gated.
abstract interface class AppOperationsStore {
  AppOperationsConfig? readConfig();
  Future<void> writeConfig(AppOperationsConfig config);

  String? readDismissedAnnouncementId();
  Future<void> writeDismissedAnnouncementId(String id);

  String? readDismissedRecommendedVersion();
  Future<void> writeDismissedRecommendedVersion(String version);
}

/// What is installed on this device.
class InstalledApp {
  const InstalledApp({required this.platform, required this.version});

  final AppPlatform platform;

  /// `x.y.z` as the build reports it, or null when unknown.
  final String? version;
}

/// Reads the installed version. An interface so tests can pin one.
abstract interface class AppVersionProvider {
  Future<InstalledApp> installed();
}
