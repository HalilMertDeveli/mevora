import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/pages/account_settings_page.dart';
import 'package:mevora/features/settings/presentation/pages/settings_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

Future<Widget> _routerHarness({
  required AuthController auth,
  required String initialLocation,
}) async {
  final language = LanguageController(
    repository: LanguageRepository(local: MemoryLanguageDataSource()),
    deviceLocale: const Locale('en'),
  );
  await language.load();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.accountSettings,
        builder: (_, _) => const AccountSettingsPage(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const SizedBox()),
    ],
  );
  return AppScope(
    config: const AppConfig(environment: AppEnvironment.development),
    logger: const AppLogger(environment: AppEnvironment.development),
    child: LanguageScope(
      controller: language,
      child: AuthScope(
        controller: auth,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: language.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    ),
  );
}

AuthController _authenticatedAuth({
  AuthProviders providers = const AuthProviders(email: true),
}) {
  final user = AuthUser(
    id: 'self',
    email: 'ada@mevora.app',
    authProviders: providers,
  );
  final auth = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: FakeUserDocumentRepository(),
    logger: const AppLogger(environment: AppEnvironment.development),
  );
  auth.user = user;
  auth.status = Authenticated(user);
  return auth;
}

void main() {
  test('account settings route is registered in app router', () {
    final source = File('lib/core/routing/app_router.dart').readAsStringSync();
    expect(source.contains("path: 'account'"), isTrue);
    expect(source.contains('AccountSettingsPage'), isTrue);
  });

  test('spotify music functions are exported from index', () {
    final source = File('functions/src/index.ts').readAsStringSync();
    expect(source.contains('spotifyLinkMusic'), isTrue);
    expect(source.contains('getMusicAccount'), isTrue);
    expect(source.contains('syncSpotifyTaste'), isTrue);
  });

  testWidgets('settings exposes linked accounts navigation', (tester) async {
    final auth = _authenticatedAuth();
    await tester.pumpWidget(
      await _routerHarness(auth: auth, initialLocation: AppRoutes.settings),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n.linkedAccounts).first);
    await tester.pumpAndSettle();

    expect(find.byType(AccountSettingsPage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(_l10n.deleteAccount),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_l10n.deleteAccount), findsOneWidget);
    auth.dispose();
  });

  Future<void> pumpAccount(WidgetTester tester, AuthController auth) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _routerHarness(
        auth: auth,
        initialLocation: AppRoutes.accountSettings,
      ),
    );
    await tester.pumpAndSettle();
  }

  // Linking Apple runs Sign in with Apple, which only exists on Apple
  // platforms: elsewhere the row would be a button that always fails.
  testWidgets(
    'linked accounts do not offer Apple on Android',
    (tester) async {
      final auth = _authenticatedAuth();
      await pumpAccount(tester, auth);

      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      auth.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'linked accounts offer Apple on iOS',
    (tester) async {
      final auth = _authenticatedAuth();
      await pumpAccount(tester, auth);

      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);
      auth.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'an Apple account linked elsewhere still shows as linked on Android',
    (tester) async {
      final auth = _authenticatedAuth(
        providers: const AuthProviders(apple: true),
      );
      await pumpAccount(tester, auth);

      expect(find.text('Apple'), findsOneWidget);
      // Shown as a fact, with nothing to tap: only Apple reads "linked".
      expect(find.text(_l10n.linked), findsOneWidget);
      auth.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('delete account navigates to login after success', (
    tester,
  ) async {
    final auth = _authenticatedAuth();
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _routerHarness(
        auth: auth,
        initialLocation: AppRoutes.accountSettings,
      ),
    );
    await tester.pumpAndSettle();

    final deleteFinder = find.text(_l10n.deleteAccount);
    await tester.scrollUntilVisible(
      deleteFinder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(deleteFinder);
    await tester.pumpAndSettle();
    await tester.tap(deleteFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.deleteConfirm));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(auth.status, isA<Unauthenticated>());
    expect(find.byType(AccountSettingsPage), findsNothing);
    auth.dispose();
  });
}
