import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
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
}
