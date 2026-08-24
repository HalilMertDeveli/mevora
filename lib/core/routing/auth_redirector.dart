import 'package:mevora/core/routing/app_routes.dart';
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

  static String? redirect({
    required AuthStatus status,
    required String location,
    bool allowDesignSystem = false,
    bool phoneChallengeActive = false,
    bool needsLocationOnboarding = false,
    bool locationGateResolved = true,
  }) {
    if (allowDesignSystem && location == AppRoutes.designSystem) {
      return null;
    }

    switch (status) {
      case AuthInitializing():
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      case Authenticating():
        return location == AppRoutes.splash ||
                _sessionRoutes.contains(location)
            ? null
            : AppRoutes.splash;
      case PhoneCodeSent() || PhoneVerificationRequired():
        return location == AppRoutes.phoneOtp ? null : AppRoutes.phoneOtp;
      case Unauthenticated() || AuthenticationError():
        if (location == AppRoutes.phoneOtp) {
          return phoneChallengeActive ? null : AppRoutes.phone;
        }
        return _sessionRoutes.contains(location) ||
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
        if (location == AppRoutes.splash ||
            location == AppRoutes.onboarding ||
            location == AppRoutes.locationPermission ||
            _sessionRoutes.contains(location) ||
            location == AppRoutes.phoneOtp) {
          return AppRoutes.discovery;
        }
        return null;
    }
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
