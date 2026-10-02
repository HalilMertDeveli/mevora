import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_account_menu.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/support/presentation/pages/legal_pages.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';

const _user = AuthUser(id: 'u1');
const _loginKey = ValueKey('login-screen');

/// Tells account deletion apart from a plain sign-out. In the app this call
/// is `AccountDeletionService.deleteAccount()` behind the auth repository.
class _RecordingAuthRepository extends FakeAuthRepository {
  _RecordingAuthRepository() : super(user: _user);

  int deleteCalls = 0;

  @override
  Future<Result<void>> deleteAccount() async {
    deleteCalls += 1;
    return super.deleteAccount();
  }
}

/// A draft that never arrives, as on a dead connection.
class _StalledOnboardingRepository extends FakeOnboardingRepository {
  @override
  Future<UserProfile?> loadDraft(String uid) =>
      Completer<UserProfile?>().future;
}

class _Harness {
  _Harness({FakeOnboardingRepository? onboarding})
    : onboarding = onboarding ?? FakeOnboardingRepository() {
    auth =
        AuthController(
            authRepository: repository,
            userDocumentRepository: FakeUserDocumentRepository(),
            logger: const AppLogger(environment: AppEnvironment.development),
          )
          ..user = _user
          ..status = const NeedsOnboarding(_user);
  }

  final repository = _RecordingAuthRepository();
  final FakeOnboardingRepository onboarding;
  late final AuthController auth;

  /// The onboarding gate as the app router applies it: the real redirect
  /// rules, re-run whenever the session changes.
  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    final services = createFakeOnboardingServices();
    final controller = OnboardingController(
      repository: onboarding,
      storage: services.storageRepository,
      photoPicker: services.photoPicker,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      refreshListenable: auth,
      redirect: (_, state) => AuthRedirector.redirect(
        status: auth.status,
        location: state.matchedLocation,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (_, _) => const OnboardingPage(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(key: _loginKey),
        ),
        GoRoute(
          path: AppRoutes.legalTerms,
          builder: (_, _) => const TermsOfServicePage(),
        ),
        GoRoute(
          path: AppRoutes.legalPrivacy,
          builder: (_, _) => const PrivacyPolicyPage(),
        ),
        GoRoute(
          path: AppRoutes.legalGuidelines,
          builder: (_, _) => const CommunityGuidelinesPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: OnboardingScope(
          repository: onboarding,
          storage: services.storageRepository,
          photoPicker: services.photoPicker,
          controller: controller,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}

/// A button of the open confirmation dialog.
Finder _dialogButton(String label) {
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(OnboardingAccountMenu));
  await tester.pumpAndSettle();
}

/// Opens the menu, picks [action], and answers the confirmation with
/// [answer].
Future<void> _choose(
  WidgetTester tester, {
  required String action,
  required String answer,
}) async {
  await _openMenu(tester);
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
  await tester.tap(_dialogButton(answer));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('account menu during onboarding', () {
    testWidgets('the first step offers the ways out and the legal pages', (
      tester,
    ) async {
      await _Harness().pump(tester);

      expect(find.byType(OnboardingAccountMenu), findsOneWidget);
      expect(find.byTooltip(l10n.more), findsOneWidget);

      await _openMenu(tester);

      for (final label in [
        l10n.communityGuidelines,
        l10n.termsOfService,
        l10n.privacyPolicy,
        l10n.logOut,
        l10n.deleteAccount,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('a member who resumes on a later step has it too', (
      tester,
    ) async {
      final onboarding = FakeOnboardingRepository()
        ..saved = const UserProfile(
          uid: 'u1',
          displayName: 'Ada',
          onboardingStep: OnboardingStep.bio,
        )
        ..savedLastName = 'Lovelace';
      await _Harness(onboarding: onboarding).pump(tester);

      expect(find.text(l10n.onboardingBioHint), findsOneWidget);
      expect(find.byType(OnboardingAccountMenu), findsOneWidget);
    });

    testWidgets('a draft that never loads does not corner the member', (
      tester,
    ) async {
      final harness = _Harness(onboarding: _StalledOnboardingRepository());
      await harness.pump(tester, settle: false);

      expect(find.text(l10n.onboardingFirstName), findsNothing);
      await tester.tap(find.byType(OnboardingAccountMenu));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l10n.logOut), findsOneWidget);
      expect(find.text(l10n.deleteAccount), findsOneWidget);
    });
  });

  group('signing out from onboarding', () {
    testWidgets('returns to the login screen', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);

      await _openMenu(tester);
      await tester.tap(find.text(l10n.logOut));
      await tester.pumpAndSettle();

      // Says what happens to the answers given so far before anything is done.
      expect(find.text(l10n.settingsLogoutTitle), findsOneWidget);
      expect(find.text(l10n.onboardingLogoutBody), findsOneWidget);
      expect(harness.repository.signOutCalls, 0);

      await tester.tap(_dialogButton(l10n.logOut));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.repository.signOutCalls, 1);
      expect(harness.repository.deleteCalls, 0);
      expect(harness.auth.status, isA<Unauthenticated>());
      expect(find.byKey(_loginKey), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('cancelling keeps the member on the step', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);

      await _openMenu(tester);
      await tester.tap(find.text(l10n.logOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      expect(harness.repository.signOutCalls, 0);
      expect(harness.auth.status, isA<NeedsOnboarding>());
      expect(find.text(l10n.onboardingFirstName), findsOneWidget);
    });

    testWidgets('asks in Turkish on a Turkish device', (tester) async {
      final tr = lookupAppLocalizations(const Locale('tr'));
      await _Harness().pump(tester, locale: const Locale('tr'));

      await _openMenu(tester);
      expect(find.text('Hesabı sil'), findsOneWidget);
      await tester.tap(find.text(tr.logOut));
      await tester.pumpAndSettle();

      expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
      expect(
        find.text(
          'Tamamladığın adımlar kaydedildi. Tekrar giriş yaptığında '
          'kaldığın yerden devam edersin.',
        ),
        findsOneWidget,
      );
    });
  });

  group('deleting the account from onboarding', () {
    testWidgets('calls the deletion service and signs out', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);

      await _openMenu(tester);
      await tester.tap(find.text(l10n.deleteAccount));
      await tester.pumpAndSettle();

      // The same confirmation as Settings, and nothing deleted before it.
      expect(find.text(l10n.deleteAccountTitle), findsOneWidget);
      expect(find.text(l10n.deleteAccountBody), findsOneWidget);
      expect(harness.repository.deleteCalls, 0);

      await tester.tap(_dialogButton(l10n.deleteConfirm));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.repository.deleteCalls, 1);
      expect(harness.repository.signedOut, isTrue);
      expect(harness.auth.status, isA<Unauthenticated>());
      expect(find.byKey(_loginKey), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final harness = _Harness();
      await harness.pump(tester);

      await _openMenu(tester);
      await tester.tap(find.text(l10n.deleteAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      expect(harness.repository.deleteCalls, 0);
      expect(harness.auth.status, isA<NeedsOnboarding>());
      expect(find.text(l10n.onboardingFirstName), findsOneWidget);
    });

    testWidgets('a failed deletion brings the step back and says so', (
      tester,
    ) async {
      final harness = _Harness();
      harness.repository.nextFailure = const AuthFailure(
        AuthMessages.network,
        kind: AuthErrorKind.network,
      );
      await harness.pump(tester);

      await _choose(
        tester,
        action: l10n.deleteAccount,
        answer: l10n.deleteConfirm,
      );

      expect(harness.repository.deleteCalls, 1);
      expect(harness.auth.status, isA<NeedsOnboarding>());
      expect(find.byKey(_loginKey), findsNothing);
      expect(find.text(l10n.onboardingFirstName), findsOneWidget);
      expect(find.text(l10n.authNetwork), findsOneWidget);
      // Still usable: the member can try again.
      expect(find.byType(OnboardingAccountMenu), findsOneWidget);
    });
  });

  group('legal pages from onboarding', () {
    testWidgets('each one opens and comes back to the same step', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.pump(tester);
      await tester.enterText(
        find.widgetWithText(TextField, l10n.onboardingFirstName),
        'Ada',
      );

      final pages = <String, Type>{
        l10n.termsOfService: TermsOfServicePage,
        l10n.privacyPolicy: PrivacyPolicyPage,
        l10n.communityGuidelines: CommunityGuidelinesPage,
      };
      for (final MapEntry(key: label, value: page) in pages.entries) {
        await _openMenu(tester);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget, reason: label);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(page), findsNothing, reason: label);
      }

      // What was typed before reading is still there.
      expect(find.text('Ada'), findsOneWidget);
      expect(harness.auth.status, isA<NeedsOnboarding>());
    });
  });
}
