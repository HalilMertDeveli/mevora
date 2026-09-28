import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/profile/profile_update_notifier.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/presentation/pages/settings_page.dart';
import 'package:mevora/features/settings/presentation/widgets/personalization_setting_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';

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

class _NoStorage implements StorageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _NoReauth implements ReauthPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value();
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

Widget _wrap(Widget child, FakeSettingsHubRepository hub, {Locale? locale}) {
  return AuthScope(
    controller: _auth(),
    child: SettingsScope(
      services: SettingsServices(
        settingsHub: hub,
        photoManager: ProfilePhotoManager(
          settingsHub: hub,
          storage: _NoStorage(),
        ),
        reauthService: _NoReauth(),
        photoPicker: const StubProfilePhotoPicker(),
        profileUpdates: ProfileUpdateNotifier(),
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale ?? const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('defaults to ON for a member who never chose', (tester) async {
    final hub = FakeSettingsHubRepository();
    await tester.pumpWidget(_wrap(const PersonalizationSettingTile(), hub));
    await tester.pumpAndSettle();

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('personalizeRecommendationsSwitch')),
    );
    expect(tile.value, isTrue);
    expect(
      find.text('Personalize my recommendations based on my interactions'),
      findsOneWidget,
    );
    expect(find.textContaining('never analyze the content'), findsOneWidget);
  });

  testWidgets('turning it OFF saves false and keeps every other setting', (
    tester,
  ) async {
    final hub = FakeSettingsHubRepository()
      ..settings = const UserSettings(
        uid: 'u1',
        languageCode: 'tr',
        matchNotifications: false,
      );
    await tester.pumpWidget(_wrap(const PersonalizationSettingTile(), hub));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('personalizeRecommendationsSwitch')));
    await tester.pumpAndSettle();

    expect(hub.settings!.personalizeRecommendations, isFalse);
    expect(hub.settings!.languageCode, 'tr');
    expect(hub.settings!.matchNotifications, isFalse);
  });

  testWidgets('shows the Turkish copy without any "AI" wording', (
    tester,
  ) async {
    final hub = FakeSettingsHubRepository();
    await tester.pumpWidget(
      _wrap(
        const PersonalizationSettingTile(),
        hub,
        locale: const Locale('tr'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Önerilerimi etkileşimlerime göre kişiselleştir'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Mesajlarının içeriğini analiz etmeyiz'),
      findsOneWidget,
    );
    expect(find.textContaining('AI'), findsNothing);
    expect(find.textContaining('yapay zeka'), findsNothing);
  });

  testWidgets('appears on the main settings page', (tester) async {
    final hub = FakeSettingsHubRepository();
    await tester.pumpWidget(_wrap(const SettingsPage(), hub));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('personalizeRecommendationsSwitch')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('personalizeRecommendationsSwitch')),
      findsOneWidget,
    );
  });

  test('copyWith keeps the switch when other fields change', () {
    const off = UserSettings(uid: 'u1', personalizeRecommendations: false);
    expect(off.copyWith(theme: 'dark').personalizeRecommendations, isFalse);
    expect(
      off.copyWith(personalizeRecommendations: true).personalizeRecommendations,
      isTrue,
    );
  });
}
