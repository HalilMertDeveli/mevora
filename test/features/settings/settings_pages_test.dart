import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/presentation/pages/change_password_page.dart';
import 'package:mevora/features/settings/presentation/pages/settings_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import '../../helpers/fake_auth.dart';
import '../../helpers/fake_settings_hub_repository.dart';

class _SilentLogger implements AppLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserDocs implements UserDocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStorage implements StorageRepository {
  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    return Success(Uri.parse('https://example.com/$path'));
  }

  @override
  Future<Result<void>> delete(String path) async => const Success(null);

  @override
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
    void Function(double progress)? onProgress,
  }) async {
    return Success(Uri.parse('https://example.com/$imageId'));
  }

  @override
  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  }) async {
    return const Success(null);
  }
}

class _FakeReauth implements ReauthPort {
  @override
  Future<void> reauthenticateWithGoogle() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}
}

AuthController _auth() {
  const user = AuthUser(
    id: 'u1',
    email: 'test@mevora.app',
    authProviders: AuthProviders(email: true),
  );
  final controller = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: _FakeUserDocs(),
    logger: _SilentLogger(),
  );
  controller.user = user;
  controller.status = const Authenticated(user);
  return controller;
}

SettingsServices _services() {
  final hub = FakeSettingsHubRepository();
  return SettingsServices(
    settingsHub: hub,
    photoManager: ProfilePhotoManager(
      settingsHub: hub,
      storage: _FakeStorage(),
    ),
    reauthService: _FakeReauth(),
    photoPicker: const StubProfilePhotoPicker(),
  );
}

Future<Widget> _wrap(Widget child) async {
  final language = LanguageController(
    repository: LanguageRepository(local: MemoryLanguageDataSource()),
    deviceLocale: const Locale('en'),
  );
  await language.load();
  return LanguageScope(
    controller: language,
    child: AuthScope(
      controller: _auth(),
      child: SettingsScope(
        services: _services(),
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: language.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    ),
  );
}

AuthController _controller(AuthUser user, FakeAuthRepository repo) {
  final controller = AuthController(
    authRepository: repo,
    userDocumentRepository: _FakeUserDocs(),
    logger: _SilentLogger(),
  );
  controller.user = user;
  controller.status = Authenticated(user);
  return controller;
}

Future<Widget> _wrapRouter({
  required AuthController auth,
  required GoRouter router,
}) async {
  final language = LanguageController(
    repository: LanguageRepository(local: MemoryLanguageDataSource()),
    deviceLocale: const Locale('en'),
  );
  await language.load();
  return AppScope(
    config: const AppConfig(environment: AppEnvironment.development),
    logger: const AppLogger(environment: AppEnvironment.development),
    child: LanguageScope(
      controller: language,
      child: AuthScope(
        controller: auth,
        child: SettingsScope(
          services: _services(),
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: language.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
}

GoRouter _logoutRouter(AuthController auth) {
  return GoRouter(
    initialLocation: AppRoutes.settings,
    refreshListenable: auth,
    redirect: (context, state) {
      return AuthRedirector.redirect(
        status: auth.status,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('Login screen')),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );
}

void main() {
  testWidgets('settings page shows account sections', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Connect Spotify'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
    expect(find.text('Hesabı sil'), findsNothing);
  });

  testWidgets('change password validates mismatch', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = AuthUser(
      id: 'u1',
      email: 'test@mevora.app',
      authProviders: AuthProviders(email: true),
    );
    final auth = AuthController(
      authRepository: FakeAuthRepository(user: user),
      userDocumentRepository: _FakeUserDocs(),
      logger: _SilentLogger(),
    );
    auth.user = user;
    auth.status = const Authenticated(user);

    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChangePasswordPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'current-pass-1');
    await tester.enterText(find.byType(TextField).at(1), 'new-pass-1234');
    await tester.enterText(find.byType(TextField).at(2), 'different-pass');
    await tester.tap(find.widgetWithText(MevoraButton, 'Change password'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('logout confirm dialog appears', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('logout success reaches login and blocks authenticated routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = AuthUser(
      id: 'u1',
      email: 'test@mevora.app',
      authProviders: AuthProviders(email: true),
      onboardingCompleted: true,
      profileCompleted: true,
    );
    final repo = FakeAuthRepository(user: user);
    final auth = _controller(user, repo);
    addTearDown(auth.dispose);
    addTearDown(repo.dispose);
    auth.start();
    final router = _logoutRouter(auth);
    addTearDown(router.dispose);

    await tester.pumpWidget(await _wrapRouter(auth: auth, router: router));
    await tester.pump();
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MevoraButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(auth.status, isA<Unauthenticated>());
    expect(auth.user, isNull);
    expect(find.text('Login screen'), findsOneWidget);

    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.text('Login screen'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('logout failure shows an error and does not crash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = AuthUser(
      id: 'u1',
      email: 'test@mevora.app',
      authProviders: AuthProviders(email: true),
      onboardingCompleted: true,
      profileCompleted: true,
    );
    final repo = FakeAuthRepository(user: user);
    repo.nextFailure = const AuthFailure('Could not log out right now.');
    final auth = _controller(user, repo);
    addTearDown(auth.dispose);
    addTearDown(repo.dispose);
    auth.start();
    final router = _logoutRouter(auth);
    addTearDown(router.dispose);

    await tester.pumpWidget(await _wrapRouter(auth: auth, router: router));
    await tester.pump();
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MevoraButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(auth.status, isA<Authenticated>());
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Could not log out right now.'), findsOneWidget);
  });

  testWidgets('double-tap logout only opens one confirm dialog', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.tap(find.text('Log out'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
