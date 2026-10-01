import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/profile/profile_update_notifier.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/domain/validators/profile_edit_validator.dart';
import 'package:mevora/features/settings/presentation/pages/edit_profile_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_profile_photo_remover.dart';
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
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Result<void>>.value(const Success(null));
}

class _FakeReauth implements ReauthPort {
  @override
  Future<void> reauthenticateWithGoogle() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}
}

/// Records which of the two stores each save went to.
class _Hub extends FakeSettingsHubRepository {
  final profileSaves = <UserProfile>[];
  final lastNameSaves = <String>[];

  @override
  Future<void> saveProfile(UserProfile next) async {
    profileSaves.add(next);
    await super.saveProfile(next);
  }

  @override
  Future<void> saveLastName(String uid, String next) async {
    lastNameSaves.add(next);
    await super.saveLastName(uid, next);
  }
}

UserProfile _profile() {
  return const UserProfile(
    uid: 'u1',
    displayName: 'Halil',
    age: 31,
    gender: 'man',
    interestedIn: 'women',
    city: 'İstanbul',
    bio: 'Coffee, books, and long walks.',
    interests: ['music', 'travel', 'food'],
    education: 'bachelors',
    relationshipGoal: 'long_term',
    lifestyleProfile: ProfileLifestyle(
      smoking: 'never',
      drinking: 'never',
      exercise: 'regularly',
      pets: 'dog',
    ),
    photos: [
      ProfilePhoto(id: '1', storagePath: 'a', isPrimary: true),
      ProfilePhoto(id: '2', storagePath: 'b', order: 1, isPrimary: false),
      ProfilePhoto(id: '3', storagePath: 'c', order: 2, isPrimary: false),
    ],
    onboardingCompleted: true,
    profileCompleted: true,
  );
}

Future<void> _openEditProfile(WidgetTester tester, _Hub hub) async {
  tester.view.physicalSize = const Size(1080, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const user = AuthUser(id: 'u1');
  final auth = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: _FakeUserDocs(),
    logger: _SilentLogger(),
  );
  auth.user = user;
  auth.status = const Authenticated(user);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => const EditProfilePage(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: SettingsScope(
        services: SettingsServices(
          settingsHub: hub,
          photoManager: ProfilePhotoManager(
            settingsHub: hub,
            storage: _FakeStorage(),
            photoRemover: FakeProfilePhotoRemover(),
          ),
          reauthService: _FakeReauth(),
          photoPicker: const StubProfilePhotoPicker(),
          profileUpdates: ProfileUpdateNotifier(),
        ),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    ),
  );
  router.go('/edit');
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(MevoraTextField, label);

void main() {
  final l10n = lookupAppLocalizations(const Locale('tr'));

  group('last name rule', () {
    test('a legacy account may leave the surname empty', () {
      expect(
        ProfileEditValidator.validateLastName('', required: false),
        isNull,
      );
      expect(
        ProfileEditValidator.validateLastName('  ', required: false),
        isNull,
      );
    });

    test('an account that has a surname cannot clear it', () {
      expect(
        ProfileEditValidator.validateLastName(' ', required: true),
        'last_name_required',
      );
    });

    test('a typed surname is always checked', () {
      expect(
        ProfileEditValidator.validateLastName('Öztürk', required: false),
        isNull,
      );
      expect(
        ProfileEditValidator.validateLastName('a' * 51, required: false),
        'last_name_too_long',
      );
      expect(
        ProfileEditValidator.validateLastName('123', required: false),
        'last_name_required',
      );
    });

    test('first name keeps its rule', () {
      expect(ProfileEditValidator.validateFirstName('Çağrı'), isNull);
      expect(
        ProfileEditValidator.validateFirstName(' '),
        'first_name_required',
      );
      expect(
        ProfileEditValidator.validateFirstName('a' * 41),
        'first_name_too_long',
      );
    });
  });

  group('Edit Profile', () {
    testWidgets('a legacy member loads and saves without a surname', (
      tester,
    ) async {
      final hub = _Hub()..profile = _profile();
      await _openEditProfile(tester, hub);

      expect(_field('Halil'), findsOneWidget);
      expect(_field(l10n.onboardingLastName), findsOneWidget);
      expect(find.text(l10n.onboardingLastNamePrivate), findsOneWidget);

      await tester.enterText(_field(l10n.onboardingFirstName), 'Halil Mert');
      await tester.pump();
      await tester.tap(find.text(l10n.saveChanges));
      await tester.pumpAndSettle();

      expect(hub.profileSaves.single.displayName, 'Halil Mert');
      expect(hub.lastNameSaves, isEmpty);
      expect(hub.lastName, isNull);
    });

    testWidgets('a surname is saved privately, apart from the profile', (
      tester,
    ) async {
      final hub = _Hub()..profile = _profile();
      await _openEditProfile(tester, hub);

      await tester.enterText(_field(l10n.onboardingLastName), '  Öztürk ');
      await tester.pump();
      await tester.tap(find.text(l10n.saveChanges));
      await tester.pumpAndSettle();

      expect(hub.lastNameSaves, ['Öztürk']);
      expect(hub.profileSaves.single.displayName, 'Halil');
    });

    testWidgets('the saved surname is shown again on the next visit', (
      tester,
    ) async {
      final hub = _Hub()
        ..profile = _profile()
        ..lastName = 'Develi';
      await _openEditProfile(tester, hub);

      expect(_field('Develi'), findsOneWidget);
      expect(_field('Halil'), findsOneWidget);
    });

    testWidgets('an existing surname cannot be cleared', (tester) async {
      final hub = _Hub()
        ..profile = _profile()
        ..lastName = 'Develi';
      await _openEditProfile(tester, hub);

      await tester.enterText(_field('Develi'), '');
      await tester.pump();
      await tester.tap(find.text(l10n.saveChanges));
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsLastNameRequired), findsOneWidget);
      expect(hub.lastNameSaves, isEmpty);
      expect(hub.profileSaves, isEmpty);
      expect(hub.lastName, 'Develi');
    });

    testWidgets('the locked date of birth comes from the private account', (
      tester,
    ) async {
      final hub = _Hub()
        ..profile = _profile()
        ..birthDate = DateTime(1995, 5, 5);
      await _openEditProfile(tester, hub);

      expect(find.text(l10n.settingsBirthDateLocked), findsOneWidget);
      expect(
        find.text(L10nFormat.mediumDate(l10n, DateTime(1995, 5, 5))),
        findsOneWidget,
      );
    });

    testWidgets('an account with no date of birth shows no such row', (
      tester,
    ) async {
      final hub = _Hub()..profile = _profile();
      await _openEditProfile(tester, hub);

      expect(find.text(l10n.settingsBirthDateLocked), findsNothing);
    });
  });
}
