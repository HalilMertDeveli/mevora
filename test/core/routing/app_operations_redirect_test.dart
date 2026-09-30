import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_router.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/learning_journey_controller.dart';

void main() {
  const member = Authenticated(AuthUser(id: 'u1', onboardingCompleted: true));

  String? go(
    AuthStatus status,
    String location, {
    AppOperationsGate gate = AppOperationsGate.normal,
    String? journeyRoute,
  }) {
    return AuthRedirector.redirect(
      status: status,
      location: location,
      operationsGate: gate,
      journeyRoute: journeyRoute,
    );
  }

  group('maintenance', () {
    const gate = AppOperationsGate.maintenance;

    test('sends members and signed-out visitors alike to maintenance', () {
      for (final status in <AuthStatus>[
        member,
        const Unauthenticated(),
        const AuthInitializing(),
        const NeedsOnboarding(AuthUser(id: 'u2')),
      ]) {
        for (final location in [
          AppRoutes.splash,
          AppRoutes.discovery,
          AppRoutes.login,
          AppRoutes.phone,
          AppRoutes.boost,
          AppRoutes.chatPath('m1'),
          AppRoutes.updateRequired,
        ]) {
          expect(
            go(status, location, gate: gate),
            AppRoutes.maintenance,
            reason: '$status at $location',
          );
        }
        expect(go(status, AppRoutes.maintenance, gate: gate), isNull);
      }
    });

    test('legal pages stay reachable for everyone', () {
      for (final location in [
        AppRoutes.legalTerms,
        AppRoutes.legalPrivacy,
        AppRoutes.legalGuidelines,
      ]) {
        expect(go(member, location, gate: gate), isNull);
        expect(go(const Unauthenticated(), location, gate: gate), isNull);
      }
    });

    test('support and account settings stay reachable for a member', () {
      for (final location in [
        AppRoutes.supportCenter,
        AppRoutes.supportFaq,
        AppRoutes.supportTicketCreate,
        AppRoutes.supportTicketDetailPath('t1'),
        AppRoutes.termsOfService,
        AppRoutes.accountSettings,
      ]) {
        expect(go(member, location, gate: gate), isNull, reason: location);
      }
      // Even mid-journey: settings are exempt from the first-run steps.
      expect(
        go(
          member,
          AppRoutes.accountSettings,
          gate: gate,
          journeyRoute: AppRoutes.humorCalibration,
        ),
        isNull,
      );
    });

    test('other settings are not part of the allow-list', () {
      expect(
        go(member, AppRoutes.editProfile, gate: gate),
        AppRoutes.maintenance,
      );
      expect(go(member, AppRoutes.settings, gate: gate), AppRoutes.maintenance);
    });

    test(
      'signed out, support goes through sign-in and back to maintenance',
      () {
        final first = go(
          const Unauthenticated(),
          AppRoutes.supportCenter,
          gate: gate,
        );
        expect(first, AppRoutes.login);
        expect(
          go(const Unauthenticated(), first!, gate: gate),
          AppRoutes.maintenance,
        );
      },
    );
  });

  group('update required', () {
    const gate = AppOperationsGate.updateRequired;

    test('everything but legal leads to the update screen', () {
      for (final status in <AuthStatus>[member, const Unauthenticated()]) {
        for (final location in [
          AppRoutes.splash,
          AppRoutes.discovery,
          AppRoutes.login,
          AppRoutes.supportCenter,
          AppRoutes.accountSettings,
          AppRoutes.maintenance,
        ]) {
          expect(
            go(status, location, gate: gate),
            AppRoutes.updateRequired,
            reason: '$status at $location',
          );
        }
        expect(go(status, AppRoutes.updateRequired, gate: gate), isNull);
        expect(go(status, AppRoutes.legalPrivacy, gate: gate), isNull);
      }
    });
  });

  group('back to normal', () {
    test('the gate screens hand over to the splash', () {
      expect(go(member, AppRoutes.maintenance), AppRoutes.splash);
      expect(go(member, AppRoutes.updateRequired), AppRoutes.splash);
      expect(
        go(const Unauthenticated(), AppRoutes.maintenance),
        AppRoutes.splash,
      );
      // …and the authentication gate takes it from there.
      expect(go(member, AppRoutes.splash), AppRoutes.discovery);
      expect(go(const Unauthenticated(), AppRoutes.splash), AppRoutes.login);
    });

    test('normal operation changes nothing else', () {
      expect(go(member, AppRoutes.discovery), isNull);
      expect(go(const Unauthenticated(), AppRoutes.login), isNull);
    });
  });

  group('journey with the Humor Lab switched off', () {
    test('skips the humor step instead of looping on its redirect', () {
      expect(
        journeyRouteFor(AppRoutes.humorCalibration, humorAvailable: false),
        LearningJourneyController.learningRoute,
      );
      expect(
        journeyRouteFor(AppRoutes.humorCalibration, humorAvailable: true),
        AppRoutes.humorCalibration,
      );
      expect(journeyRouteFor(null, humorAvailable: false), isNull);
    });
  });
}
