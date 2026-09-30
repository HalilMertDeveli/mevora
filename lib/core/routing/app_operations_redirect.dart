import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';

/// What the operations gate decided for one navigation.
///
/// [decided] false means "no opinion": the normal authentication rules
/// apply. When [decided] is true, [target] is the answer (null = stay).
class AppOperationsDecision {
  const AppOperationsDecision._(this.decided, this.target);

  static const AppOperationsDecision pass = AppOperationsDecision._(
    false,
    null,
  );
  static const AppOperationsDecision stay = AppOperationsDecision._(true, null);

  const AppOperationsDecision.go(String target) : this._(true, target);

  final bool decided;
  final String? target;
}

/// Pure routing rules for maintenance and required updates. Runs before the
/// authentication gate and applies whether or not anyone is signed in.
///
/// - Update required: only the update screen and the public legal pages.
/// - Maintenance: the maintenance screen and the public legal pages, plus
///   support and account settings (deletion, data export) — which still go
///   through the normal sign-in rules, so a signed-out member lands back on
///   the maintenance screen rather than on a sign-in form.
/// - Normal: the two gate screens send everyone back through the splash, and
///   the authentication gate takes over from there.
abstract final class AppOperationsRedirect {
  static const Set<String> _publicLegalRoutes = {
    AppRoutes.legalTerms,
    AppRoutes.legalPrivacy,
    AppRoutes.legalGuidelines,
  };

  static bool _maintenanceAllows(String location) {
    return location == AppRoutes.supportCenter ||
        location.startsWith('${AppRoutes.supportCenter}/') ||
        location == AppRoutes.accountSettings;
  }

  static AppOperationsDecision evaluate({
    required AppOperationsGate gate,
    required String location,
  }) {
    switch (gate) {
      case AppOperationsGate.normal:
        return location == AppRoutes.maintenance ||
                location == AppRoutes.updateRequired
            ? const AppOperationsDecision.go(AppRoutes.splash)
            : AppOperationsDecision.pass;
      case AppOperationsGate.updateRequired:
        return location == AppRoutes.updateRequired ||
                _publicLegalRoutes.contains(location)
            ? AppOperationsDecision.stay
            : const AppOperationsDecision.go(AppRoutes.updateRequired);
      case AppOperationsGate.maintenance:
        if (location == AppRoutes.maintenance ||
            _publicLegalRoutes.contains(location)) {
          return AppOperationsDecision.stay;
        }
        return _maintenanceAllows(location)
            ? AppOperationsDecision.pass
            : const AppOperationsDecision.go(AppRoutes.maintenance);
    }
  }
}
