import 'package:mevora/features/app_operations/domain/app_operations_config.dart';

/// Whether the app is usable right now, as the router sees it.
enum AppOperationsGate { normal, maintenance, updateRequired }

/// A required update wins over maintenance: it is specific to this build and
/// the member can act on it straight away, while maintenance will still be
/// there — or already over — once they have updated.
AppOperationsGate resolveAppOperationsGate({
  required AppOperationsConfig config,
  required VersionGate versionGate,
}) {
  if (versionGate == VersionGate.updateRequired) {
    return AppOperationsGate.updateRequired;
  }
  if (config.maintenanceEnabled) {
    return AppOperationsGate.maintenance;
  }
  return AppOperationsGate.normal;
}
