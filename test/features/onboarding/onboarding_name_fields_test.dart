import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/data/datasources/firebase_user_data_source.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/data/repositories/onboarding_repository_impl.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_error_l10n.dart';
import 'package:mevora/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/validators/person_name_validator.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/pump_app.dart';

/// Stands in for the `completeOnboarding` callable.
class _Backend implements BackendCallable {
  _Backend(this._profiles, {this.rejectWith});

  final FakeProfileRepository _profiles;
  final String? rejectWith;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add(name);
    final reason = rejectWith;
    if (reason != null) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: reason,
      );
    }
    final uid = _profiles.profiles.keys.single;
    _profiles.profiles[uid] = _profiles.profiles[uid]!.copyWith(
      onboardingCompleted: true,
      profileCompleted: true,
    );
    return {'ok': true};
  }
}

UserProfile _basicInfo({String displayName = 'Halil'}) {
  return UserProfile(
    uid: 'u1',
    displayName: displayName,
    birthDate: DateTime(1995, 5, 5),
    gender: 'man',
    interestedIn: 'women',
    city: 'İstanbul',
  );
}

UserProfile _complete() {
  return _basicInfo().copyWith(
    interests: const ['music', 'travel', 'food'],
    education: 'bachelors',
    relationshipGoal: 'long_term',
    lifestyleProfile: const ProfileLifestyle(
      smoking: 'never',
      drinking: 'never',
      exercise: 'regularly',
      pets: 'dog',
    ),
    bio: 'Coffee, books, and long walks.',
    photos: [
      for (var i = 0; i < OnboardingConfig.minPhotos; i++)
        ProfilePhoto(id: '$i', storagePath: 'path/$i'),
    ],
  );
}

String? _message(Result<void> result) => result.failureOrNull?.message;

Future<void> _pumpOnboarding(
  WidgetTester tester,
  OnboardingController controller, {
  Locale locale = const Locale('tr'),
}) async {
  final services = createFakeOnboardingServices();
  // Signed in, so the page loads the draft itself, as it does in the app.
  const user = AuthUser(id: 'u1');
  final auth = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: FakeUserDocumentRepository(),
    logger: const AppLogger(environment: AppEnvironment.development),
  )..user = user;
  await tester.pumpWidget(
    wrapWithApp(
      AuthScope(
        controller: auth,
        child: OnboardingScope(
          repository: services.onboardingRepository,
          storage: services.storageRepository,
          photoPicker: services.photoPicker,
          controller: controller,
          child: const OnboardingPage(),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('basic info validation', () {
    test('first name is required', () {
      for (final firstName in ['', '   ']) {
        expect(
          _message(
            OnboardingValidators.validateBasicInfo(
              _basicInfo(displayName: firstName),
              lastName: 'Develi',
            ),
          ),
          OnboardingMessages.firstNameRequired,
        );
      }
    });

    test('last name is required', () {
      for (final lastName in [null, '', '   ']) {
        expect(
          _message(
            OnboardingValidators.validateBasicInfo(
              _basicInfo(),
              lastName: lastName,
            ),
          ),
          OnboardingMessages.lastNameRequired,
        );
      }
    });

    test('Turkish names pass, padded with whitespace or not', () {
      expect(
        OnboardingValidators.validateBasicInfo(
          _basicInfo(displayName: '  Çağrı Gökçe '),
          lastName: '  Öztürk-Şahin  ',
        ).isSuccess,
        isTrue,
      );
    });

    test('an over-long name is refused', () {
      expect(
        _message(
          OnboardingValidators.validateBasicInfo(
            _basicInfo(
              displayName: 'a' * (PersonNameValidator.maxFirstNameLength + 1),
            ),
            lastName: 'Develi',
          ),
        ),
        OnboardingMessages.firstNameTooLong,
      );
      expect(
        _message(
          OnboardingValidators.validateBasicInfo(
            _basicInfo(),
            lastName: 'a' * (PersonNameValidator.maxLastNameLength + 1),
          ),
        ),
        OnboardingMessages.lastNameTooLong,
      );
    });

    test('completion needs the surname too', () {
      expect(
        OnboardingValidators.validateCompletion(
          _complete(),
          lastName: 'Develi',
        ).isSuccess,
        isTrue,
      );
      expect(
        _message(
          OnboardingValidators.validateCompletion(_complete(), lastName: ''),
        ),
        OnboardingMessages.lastNameRequired,
      );
    });

    test('name failures are shown in the member language', () {
      final tr = lookupAppLocalizations(const Locale('tr'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        OnboardingErrorL10n.message(tr, OnboardingMessages.lastNameRequired),
        'Soyadını ekle.',
      );
      expect(
        OnboardingErrorL10n.message(en, OnboardingMessages.lastNameRequired),
        'Add your last name.',
      );
      for (final raw in [
        OnboardingMessages.firstNameTooLong,
        OnboardingMessages.lastNameTooLong,
      ]) {
        expect(OnboardingErrorL10n.message(tr, raw), isNot(raw));
        expect(OnboardingErrorL10n.message(en, raw), isNot(raw));
      }
    });
  });

  group('saving the name', () {
    test('the surname goes to the private account, not the profile', () async {
      final profiles = FakeProfileRepository();
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: _Backend(profiles),
      );

      final result = await repository.saveStep(
        profile: _basicInfo(displayName: '  Halil '),
        step: OnboardingStep.basicInfo,
        lastName: '  Develi ',
      );

      expect(result.isSuccess, isTrue);
      expect(profiles.lastNames['u1'], 'Develi');
      final public = FirebaseProfileDataSource.publicProfileMap(
        profiles.profiles['u1']!,
      );
      expect(public['displayName'], 'Halil');
      expect(public.toString(), isNot(contains('Develi')));
      expect(await repository.loadLastName('u1'), 'Develi');
    });

    test('nothing is saved while the surname is missing', () async {
      final profiles = FakeProfileRepository();
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: _Backend(profiles),
      );

      final result = await repository.saveStep(
        profile: _basicInfo(),
        step: OnboardingStep.basicInfo,
        lastName: '  ',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(
        result.failureOrNull!.message,
        OnboardingMessages.lastNameRequired,
      );
      expect(profiles.profiles, isEmpty);
      expect(profiles.lastNames, isEmpty);
    });

    test('later steps do not rewrite the surname', () async {
      final profiles = FakeProfileRepository()..lastNames['u1'] = 'Develi';
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: _Backend(profiles),
      );

      final result = await repository.saveStep(
        profile: _complete(),
        step: OnboardingStep.interests,
        lastName: 'Someone Else',
      );

      expect(result.isSuccess, isTrue);
      expect(profiles.lastNames['u1'], 'Develi');
    });

    test('completion stops on the client without a surname', () async {
      final profiles = FakeProfileRepository();
      final backend = _Backend(profiles);
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: backend,
      );

      final result = await repository.complete(_complete(), lastName: null);

      expect(
        result.failureOrNull!.message,
        OnboardingMessages.lastNameRequired,
      );
      expect(backend.calls, isEmpty);
    });

    test('a server refusal for the surname reaches the member', () async {
      final profiles = FakeProfileRepository();
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: _Backend(profiles, rejectWith: 'last-name-required'),
      );

      final result = await repository.complete(_complete(), lastName: 'Develi');

      expect(
        result.failureOrNull!.message,
        OnboardingMessages.lastNameRequired,
      );
    });

    test('completion succeeds with both names', () async {
      final profiles = FakeProfileRepository();
      final backend = _Backend(profiles);
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: backend,
      );

      final result = await repository.complete(_complete(), lastName: 'Develi');

      expect(result.isSuccess, isTrue);
      expect(backend.calls, ['completeOnboarding']);
    });
  });

  group('onboarding controller', () {
    OnboardingController controllerFor(FakeOnboardingRepository repository) {
      final services = createFakeOnboardingServices();
      return OnboardingController(
        repository: repository,
        storage: services.storageRepository,
        photoPicker: services.photoPicker,
      );
    }

    test('both names survive an app restart mid-onboarding', () async {
      final profiles = FakeProfileRepository();
      final repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: _Backend(profiles),
      );
      final services = createFakeOnboardingServices();
      OnboardingController open() => OnboardingController(
        repository: repository,
        storage: services.storageRepository,
        photoPicker: services.photoPicker,
      );

      final first = open();
      addTearDown(first.dispose);
      await first.initialize(const AuthUser(id: 'u1'));
      first.updateDraft((_) => _basicInfo(displayName: 'Çağrı'));
      first.updateLastName('Öztürk');
      expect((await first.continueStep()).isSuccess, isTrue);
      expect(first.step, OnboardingStep.interests);

      final restarted = open();
      addTearDown(restarted.dispose);
      await restarted.initialize(const AuthUser(id: 'u1'));

      expect(restarted.profile!.displayName, 'Çağrı');
      expect(restarted.lastName, 'Öztürk');
      expect(restarted.step, OnboardingStep.interests);
    });

    test('continuing without a surname stays on the first step', () async {
      final profiles = FakeProfileRepository();
      final services = createFakeOnboardingServices();
      final controller = OnboardingController(
        repository: OnboardingRepositoryImpl(
          profiles: profiles,
          backend: _Backend(profiles),
        ),
        storage: services.storageRepository,
        photoPicker: services.photoPicker,
      );
      addTearDown(controller.dispose);
      await controller.initialize(const AuthUser(id: 'u1'));
      controller.updateDraft((_) => _basicInfo());

      final result = await controller.continueStep();

      expect(result.isError, isTrue);
      expect(controller.step, OnboardingStep.basicInfo);
      expect(controller.errorMessage, OnboardingMessages.lastNameRequired);
    });

    test(
      'a draft from before the surname existed resumes on step one',
      () async {
        final repository = FakeOnboardingRepository()
          ..saved = _complete().copyWith(onboardingStep: OnboardingStep.bio);
        final controller = controllerFor(repository);
        addTearDown(controller.dispose);

        await controller.initialize(const AuthUser(id: 'u1'));

        expect(controller.lastName, isEmpty);
        expect(controller.step, OnboardingStep.basicInfo);
        // The first name they already gave is kept as-is, never split.
        expect(controller.profile!.displayName, 'Halil');
      },
    );

    test('a saved draft with a surname resumes where it stopped', () async {
      final repository = FakeOnboardingRepository()
        ..saved = _complete().copyWith(onboardingStep: OnboardingStep.bio)
        ..savedLastName = 'Develi';
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);

      await controller.initialize(const AuthUser(id: 'u1'));

      expect(controller.step, OnboardingStep.bio);
      expect(controller.lastName, 'Develi');
    });

    test('a legacy full display name is not split into a surname', () async {
      final repository = FakeOnboardingRepository()
        ..saved = _basicInfo(displayName: 'Ayşe Nur Yılmaz');
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);

      await controller.initialize(const AuthUser(id: 'u1'));

      expect(controller.profile!.displayName, 'Ayşe Nur Yılmaz');
      expect(controller.lastName, isEmpty);
    });
  });

  group('basic info step', () {
    for (final (locale, firstName, lastName, helper) in [
      (
        const Locale('tr'),
        'Adın',
        'Soyadın',
        'Soyadın diğer üyelere gösterilmez.',
      ),
      (
        const Locale('en'),
        'First name',
        'Last name',
        'Other members never see your last name.',
      ),
    ]) {
      testWidgets('shows separate first and last name fields ($locale)', (
        tester,
      ) async {
        final services = createFakeOnboardingServices();
        addTearDown(services.controller.dispose);
        await services.controller.initialize(const AuthUser(id: 'u1'));

        await _pumpOnboarding(tester, services.controller, locale: locale);

        expect(find.widgetWithText(MevoraTextField, firstName), findsOneWidget);
        expect(find.widgetWithText(MevoraTextField, lastName), findsOneWidget);
        expect(find.text(helper), findsOneWidget);
      });
    }

    testWidgets('each field feeds its own value', (tester) async {
      final services = createFakeOnboardingServices();
      final controller = services.controller;
      addTearDown(controller.dispose);
      await controller.initialize(const AuthUser(id: 'u1'));
      await _pumpOnboarding(tester, controller);

      await tester.enterText(
        find.widgetWithText(MevoraTextField, 'Adın'),
        'Çağrı',
      );
      await tester.enterText(
        find.widgetWithText(MevoraTextField, 'Soyadın'),
        'Öztürk',
      );
      await tester.pump();

      expect(controller.profile!.displayName, 'Çağrı');
      expect(controller.lastName, 'Öztürk');
    });

    testWidgets('a restored surname is shown in its field', (tester) async {
      final repository = FakeOnboardingRepository()
        ..saved = _basicInfo()
        ..savedLastName = 'Develi';
      final services = createFakeOnboardingServices();
      final controller = OnboardingController(
        repository: repository,
        storage: services.storageRepository,
        photoPicker: services.photoPicker,
      );
      addTearDown(controller.dispose);
      await controller.initialize(const AuthUser(id: 'u1'));
      await _pumpOnboarding(tester, controller);

      expect(find.widgetWithText(MevoraTextField, 'Develi'), findsOneWidget);
      expect(find.widgetWithText(MevoraTextField, 'Halil'), findsOneWidget);
    });
  });

  group('public profile stays surname-free', () {
    // Mirrors profileCreateKeysAllowed in firebase/firestore.rules.
    const publicKeys = {
      'uid',
      'displayName',
      'birthDate',
      'age',
      'gender',
      'interestedIn',
      'bio',
      'photos',
      'interests',
      'relationshipGoal',
      'occupation',
      'education',
      'languages',
      'hobbies',
      'heightCm',
      'city',
      'lifestyle',
      'lifestyleProfile',
      'onboardingStep',
      'updatedAt',
    };

    test('the profile write carries no name field besides displayName', () {
      final map = FirebaseProfileDataSource.publicProfileMap(_complete());

      expect(publicKeys.containsAll(map.keys), isTrue, reason: '${map.keys}');
      for (final key in ['lastName', 'firstName', 'surname', 'familyName']) {
        expect(map.containsKey(key), isFalse, reason: key);
      }
    });

    test('the surname is read only from the account document', () {
      expect(
        FirebaseProfileDataSource.lastNameFrom({'lastName': '  Develi '}),
        'Develi',
      );
      // Legacy account: displayName only.
      expect(
        FirebaseProfileDataSource.lastNameFrom({'displayName': 'Halil Develi'}),
        isNull,
      );
      expect(FirebaseProfileDataSource.lastNameFrom({'lastName': ' '}), isNull);
      expect(FirebaseProfileDataSource.lastNameFrom({'lastName': 7}), isNull);
      expect(FirebaseProfileDataSource.lastNameFrom(null), isNull);
    });

    test('a provider full name seeds only the first name publicly', () {
      const session = AuthSession(
        uid: 'u1',
        provider: AuthProviderId.google,
        displayName: 'Halil Develi',
      );
      expect(FirebaseUserDataSource.publicFirstName(session), 'Halil');
    });
  });
}
