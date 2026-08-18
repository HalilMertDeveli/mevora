import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';

void main() {
  const challenge = PhoneChallenge(
    verificationId: 'vid',
    e164Phone: '+905551112233',
    maskedPhone: '+90 5•• ••• •• 33',
  );

  test('unknown auth stays on splash', () {
    expect(
      AuthRedirector.redirect(
        status: const AuthInitializing(),
        location: AppRoutes.splash,
      ),
      isNull,
    );
    expect(
      AuthRedirector.redirect(
        status: const AuthInitializing(),
        location: AppRoutes.login,
      ),
      AppRoutes.splash,
    );
  });

  test('signed-out users are sent to login', () {
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.splash,
      ),
      AppRoutes.login,
    );
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.register,
      ),
      isNull,
    );
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.phone,
      ),
      isNull,
    );
  });

  test('otp screen without a challenge returns to phone entry', () {
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.phoneOtp,
      ),
      AppRoutes.phone,
    );
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.phoneOtp,
        phoneChallengeActive: true,
      ),
      isNull,
    );
  });

  test('code-sent state opens the otp screen', () {
    expect(
      AuthRedirector.redirect(
        status: const PhoneCodeSent(challenge),
        location: AppRoutes.phone,
      ),
      AppRoutes.phoneOtp,
    );
  });

  test('authenticating stays on login instead of bouncing to splash', () {
    expect(
      AuthRedirector.redirect(
        status: const Authenticating(provider: 'email'),
        location: AppRoutes.login,
      ),
      isNull,
    );
  });

  test('needs-onboarding status opens the onboarding gate', () {
    const user = AuthUser(id: 'u1');
    expect(
      AuthRedirector.redirect(
        status: const NeedsOnboarding(user),
        location: AppRoutes.splash,
      ),
      AppRoutes.onboarding,
    );
  });

  test('incomplete profiles are gated to onboarding', () {
    const user = AuthUser(id: 'u1', onboardingCompleted: false);
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.discovery,
      ),
      AppRoutes.onboarding,
    );
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.onboarding,
      ),
      isNull,
    );
  });

  test('complete profiles leave auth screens for discovery', () {
    const user = AuthUser(id: 'u1', onboardingCompleted: true);
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.login,
      ),
      AppRoutes.discovery,
    );
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.discovery,
      ),
      isNull,
    );
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.matches,
      ),
      isNull,
    );
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.chatPath('a_b'),
      ),
      isNull,
    );
  });

  test('design system stays available only when allowed', () {
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.designSystem,
        allowDesignSystem: true,
      ),
      isNull,
    );
    expect(
      AuthRedirector.redirect(
        status: const Unauthenticated(),
        location: AppRoutes.designSystem,
      ),
      AppRoutes.login,
    );
  });

  test('new users see location permission before onboarding', () {
    const user = AuthUser(id: 'u1');
    expect(
      AuthRedirector.redirect(
        status: const NeedsOnboarding(user),
        location: AppRoutes.onboarding,
        needsLocationOnboarding: true,
      ),
      AppRoutes.locationPermission,
    );
    expect(
      AuthRedirector.redirect(
        status: const NeedsOnboarding(user),
        location: AppRoutes.locationPermission,
        needsLocationOnboarding: true,
      ),
      isNull,
    );
  });

  test('existing users skip location when the gate is satisfied', () {
    const user = AuthUser(
      id: 'u1',
      onboardingCompleted: true,
      profileCompleted: true,
    );
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.splash,
        needsLocationOnboarding: false,
      ),
      AppRoutes.discovery,
    );
    expect(
      AuthRedirector.redirect(
        status: const Authenticated(user),
        location: AppRoutes.discovery,
        needsLocationOnboarding: true,
      ),
      AppRoutes.locationPermission,
    );
  });

  test('unresolved location gate stays on splash', () {
    expect(
      AuthRedirector.redirect(
        status: const NeedsOnboarding(AuthUser(id: 'u1')),
        location: AppRoutes.onboarding,
        locationGateResolved: false,
      ),
      AppRoutes.splash,
    );
  });
}
