import 'package:mevora/core/routing/app_operations_redirect.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';

/// Pure redirect rules for the authentication gate.
abstract final class AuthRedirector {
  static const Set<String> _sessionRoutes = {
    AppRoutes.login,
    AppRoutes.register,
    AppRoutes.passwordReset,
    AppRoutes.phone,
  };

  static const Set<String> _publicLegalRoutes = {
    AppRoutes.legalTerms,
    AppRoutes.legalPrivacy,
    AppRoutes.legalGuidelines,
  };

  /// QA login behaves as a session route, but only while the gate is open, so
  /// it can never widen the unauthenticated surface in a production build.
  static bool _isSessionRoute(String location, bool qaLoginEnabled) {
    return _sessionRoutes.contains(location) ||
        (qaLoginEnabled && location == AppRoutes.qaLogin);
  }

  static String? redirect({
    required AuthStatus status,
    required String location,
    bool allowDesignSystem = false,
    bool qaLoginEnabled = false,
    bool phoneChallengeActive = false,
    bool needsLocationOnboarding = false,
    bool locationGateResolved = true,
    String? journeyRoute,
    bool journeyPending = false,
    AppOperationsGate operationsGate = AppOperationsGate.normal,
  }) {
    if (allowDesignSystem && location == AppRoutes.designSystem) {
      return null;
    }

    // Route-level guard. Hiding the button is not the defence: with the gate
    // closed this path is not navigable at all, however it is reached —
    // deep link, restored location, or a hand-typed URL.
    if (location == AppRoutes.qaLogin && !qaLoginEnabled) {
      return AppRoutes.login;
    }

    // Maintenance and required updates come before sign-in state.
    final operations = AppOperationsRedirect.evaluate(
      gate: operationsGate,
      location: location,
    );
    if (operations.decided) {
      return operations.target;
    }

    switch (status) {
      case AuthInitializing():
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      case Authenticating():
        return location == AppRoutes.splash ||
                _isSessionRoute(location, qaLoginEnabled)
            ? null
            : AppRoutes.splash;
      case PhoneCodeSent() || PhoneVerificationRequired():
        return location == AppRoutes.phoneOtp ? null : AppRoutes.phoneOtp;
      case Unauthenticated() || AuthenticationError():
        if (location == AppRoutes.phoneOtp) {
          return phoneChallengeActive ? null : AppRoutes.phone;
        }
        return _isSessionRoute(location, qaLoginEnabled) ||
                _publicLegalRoutes.contains(location)
            ? null
            : AppRoutes.login;
      case NeedsOnboarding():
        return _onboardingRedirect(
          location: location,
          needsLocationOnboarding: needsLocationOnboarding,
          locationGateResolved: locationGateResolved,
        );
      case Authenticated(:final user):
        final complete =
            user.onboardingCompleted || user.profileCompleted;
        if (!complete) {
          return _onboardingRedirect(
            location: location,
            needsLocationOnboarding: needsLocationOnboarding,
            locationGateResolved: locationGateResolved,
          );
        }
        if (!locationGateResolved) {
          return location == AppRoutes.splash ? null : AppRoutes.splash;
        }
        if (needsLocationOnboarding) {
          return location == AppRoutes.locationPermission
              ? null
              : AppRoutes.locationPermission;
        }
        final entry =
            location == AppRoutes.splash ||
            location == AppRoutes.onboarding ||
            location == AppRoutes.locationPermission ||
            _isSessionRoute(location, qaLoginEnabled) ||
            location == AppRoutes.phoneOtp;
        // A new member's first-run steps come before the rest of the app.
        // Settings, legal pages and the steps themselves stay reachable, so
        // nobody is ever cornered; everything else leads back to the step.
        if (journeyRoute != null) {
          return !entry && _journeyAllows(location) ? null : journeyRoute;
        }
        if (entry) {
          // Hold briefly on the splash while the journey is first read, so a
          // new member does not flash through Discover.
          if (journeyPending) {
            return location == AppRoutes.splash ? null : AppRoutes.splash;
          }
          return AppRoutes.discovery;
        }
        return null;
    }
  }

  static bool _journeyAllows(String location) {
    return location == AppRoutes.humorLab ||
        location.startsWith('/humor/') ||
        location == AppRoutes.relationshipLearning ||
        location.startsWith(AppRoutes.settings) ||
        _publicLegalRoutes.contains(location);
  }

  static String? _onboardingRedirect({
    required String location,
    required bool needsLocationOnboarding,
    required bool locationGateResolved,
  }) {
    if (!locationGateResolved) {
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    }
    if (needsLocationOnboarding) {
      return location == AppRoutes.locationPermission
          ? null
          : AppRoutes.locationPermission;
    }
    return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
  }
}
