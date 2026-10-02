import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/presentation/pages/discovery_preferences_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

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

/// The page under test never touches photos.
class _NoPhotoManager implements ProfilePhotoManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeReauth implements ReauthPort {
  @override
  Future<void> reauthenticateWithGoogle() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}
}

const _uid = 'u1';

Widget _page(FakeSettingsHubRepository hub) {
  const user = AuthUser(
    id: _uid,
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
  return AuthScope(
    controller: auth,
    child: SettingsScope(
      services: SettingsServices(
        settingsHub: hub,
        photoManager: _NoPhotoManager(),
        reauthService: _FakeReauth(),
        photoPicker: const StubProfilePhotoPicker(),
        profileUpdates: ProfileUpdateNotifier(),
      ),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The page closes itself after a save, so it needs a page under it.
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => context.push('/preferences'),
                  child: const Text('open'),
                ),
              ),
            ),
            GoRoute(
              path: '/preferences',
              builder: (_, _) => const DiscoveryPreferencesPage(),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, FakeSettingsHubRepository hub) async {
  await tester.pumpWidget(_page(hub));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The text fields in the order the page lays them out.
List<String> _fieldValues(WidgetTester tester) => tester
    .widgetList<MevoraTextField>(find.byType(MevoraTextField))
    .map((field) => field.controller!.text)
    .toList();

void main() {
  testWidgets(
    'shows the stored distance when the stored ages are the defaults',
    (tester) async {
      final hub = FakeSettingsHubRepository()
        ..preferences = const UserPreferences(uid: _uid, maxDistance: 20);

      await _open(tester, hub);

      expect(_fieldValues(tester), ['18', '99', '20']);
    },
  );

  testWidgets('saving another field keeps the stored distance', (tester) async {
    final hub = FakeSettingsHubRepository()
      ..preferences = const UserPreferences(uid: _uid, maxDistance: 20);

    await _open(tester, hub);
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(hub.preferences!.maxAge, 45);
    expect(hub.preferences!.maxDistance, 20);
  });

  testWidgets('what the member typed is not overwritten by a rebuild', (
    tester,
  ) async {
    final hub = FakeSettingsHubRepository()
      ..preferences = const UserPreferences(
        uid: _uid,
        minAge: 25,
        maxAge: 40,
        maxDistance: 30,
      );

    await _open(tester, hub);
    await tester.enterText(find.byType(TextField).at(2), '15');
    // Choosing a dropdown value rebuilds the page and reloads the preferences.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('everyone').last);
    await tester.pumpAndSettle();

    expect(_fieldValues(tester), ['25', '40', '15']);
  });

  testWidgets('says what the distance does', (tester) async {
    await _open(tester, FakeSettingsHubRepository());

    expect(find.text('Preferred distance (km)'), findsOneWidget);
    expect(
      find.textContaining('People inside this distance come first'),
      findsOneWidget,
    );
  });

  testWidgets('the explanation wraps instead of being cut off', (tester) async {
    await _open(tester, FakeSettingsHubRepository());

    final hint = find.textContaining('People inside this distance come first');
    final paragraph = tester.renderObject<RenderParagraph>(hint);
    expect(paragraph.didExceedMaxLines, isFalse);
    // It does not fit on one line here, and gets the lines it needs.
    expect(
      tester.getSize(hint).height,
      greaterThan(paragraph.preferredLineHeight),
    );
  });
}
