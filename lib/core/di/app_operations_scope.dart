import 'package:flutter/widgets.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/app_operations/data/app_operations_stores.dart';
import 'package:mevora/features/app_operations/data/firestore_app_operations_repository.dart';
import 'package:mevora/features/app_operations/data/package_info_app_version_provider.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_repository.dart';
import 'package:mevora/features/app_operations/presentation/controllers/app_operations_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single access point for the server-owned app operations state.
class AppOperationsScope extends InheritedNotifier<AppOperationsController> {
  const AppOperationsScope({
    super.key,
    required AppOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, subscribing to its changes. Null when not wired
  /// (widget tests, previews) — callers then behave as in normal operation.
  static AppOperationsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppOperationsScope>()
        ?.notifier;
  }

  /// Whether [feature] is on. Without a scope every feature is on, so
  /// widgets and tests that never wire operations keep working unchanged.
  static bool isFeatureEnabled(BuildContext context, AppFeature feature) {
    return maybeOf(context)?.isFeatureEnabled(feature) ?? true;
  }
}

/// Wires the operations client: the live Firestore document, the device
/// cache and the installed version. Nothing here touches the network until
/// the app calls [AppOperationsController.start].
AppOperationsController createAppOperationsController({
  SharedPreferences? preferences,
  AppOperationsRepository? repository,
  AppOperationsStore? store,
  AppVersionProvider? versionProvider,
  AppLogger? logger,
}) {
  return AppOperationsController(
    repository: repository ?? FirestoreAppOperationsRepository(),
    store:
        store ??
        (preferences == null
            ? MemoryAppOperationsStore()
            : SharedPreferencesAppOperationsStore(preferences)),
    versionProvider: versionProvider ?? const PackageInfoAppVersionProvider(),
    logger: logger,
  );
}
