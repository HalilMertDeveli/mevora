import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';

const _member = AuthUser(
  id: 'user-1',
  profileCompleted: true,
  onboardingCompleted: true,
);

final _suspended = Authenticated(
  _member.copyWith(isActive: false, accountStatus: AccountStatus.suspended),
);

const _active = Authenticated(_member);

String? _redirect(
  AuthStatus status,
  String location, {
  bool needsLocationOnboarding = false,
  bool locationGateResolved = true,
  String? journeyRoute,
}) {
  return AuthRedirector.redirect(
    status: status,
    location: location,
    needsLocationOnboarding: needsLocationOnboarding,
    locationGateResolved: locationGateResolved,
    journeyRoute: journeyRoute,
  );
}

void main() {
  group('a suspended member', () {
    test('is held on the restricted screen', () {
      for (final location in const [
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.discovery,
        AppRoutes.matches,
        AppRoutes.profile,
        AppRoutes.settings,
        AppRoutes.editProfile,
        AppRoutes.premium,
        '/chat/a_b',
        '/call/incoming/c1',
        AppRoutes.onboarding,
        AppRoutes.humorLab,
      ]) {
        expect(
          _redirect(_suspended, location),
          AppRoutes.accountRestricted,
          reason: location,
        );
      }
    });

    test('can reach appeals, support, legal pages and data controls', () {
      for (final location in [
        AppRoutes.accountRestricted,
        AppRoutes.moderationStatus,
        AppRoutes.supportCenter,
        AppRoutes.supportFaq,
        AppRoutes.supportTickets,
        AppRoutes.supportTicketCreate,
        AppRoutes.supportTicketDetailPath('t1'),
        AppRoutes.communityGuidelines,
        AppRoutes.termsOfService,
        AppRoutes.privacyPolicy,
        AppRoutes.legalTerms,
        AppRoutes.legalPrivacy,
        AppRoutes.legalGuidelines,
        AppRoutes.accountSettings,
      ]) {
        expect(_redirect(_suspended, location), isNull, reason: location);
      }
    });

    test('is not sent through onboarding, location or journey steps', () {
      final incomplete = Authenticated(
        const AuthUser(
          id: 'user-2',
        ).copyWith(isActive: false, accountStatus: AccountStatus.suspended),
      );
      expect(
        _redirect(incomplete, AppRoutes.splash),
        AppRoutes.accountRestricted,
      );
      expect(
        _redirect(
          _suspended,
          AppRoutes.discovery,
          needsLocationOnboarding: true,
        ),
        AppRoutes.accountRestricted,
      );
      expect(
        _redirect(_suspended, AppRoutes.splash, locationGateResolved: false),
        AppRoutes.accountRestricted,
      );
      expect(
        _redirect(
          _suspended,
          AppRoutes.discovery,
          journeyRoute: AppRoutes.humorLab,
        ),
        AppRoutes.accountRestricted,
      );
    });

    test('allow-list does not match look-alike paths', () {
      expect(
        AuthRedirector.restrictedAccountAllows('/settings/supportx'),
        isFalse,
      );
      expect(AuthRedirector.restrictedAccountAllows('/settings'), isFalse);
    });
  });

  group('restore', () {
    test('an active member on the restricted screen is released', () {
      expect(_redirect(_active, AppRoutes.accountRestricted), AppRoutes.splash);
      // ...and the splash then enters the normal flow.
      expect(_redirect(_active, AppRoutes.splash), AppRoutes.discovery);
    });

    test('an active member is never held', () {
      expect(_redirect(_active, AppRoutes.discovery), isNull);
      expect(_redirect(_active, AppRoutes.moderationStatus), isNull);
    });

    test('a signed-out visitor cannot open the restricted screen', () {
      expect(
        _redirect(const Unauthenticated(), AppRoutes.accountRestricted),
        AppRoutes.login,
      );
    });
  });
}
