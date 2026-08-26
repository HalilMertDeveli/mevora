import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/onboarding/data/repositories/onboarding_repository_impl.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/fake_profile_repository.dart';

class _ScriptedBackend implements BackendCallable {
  _ScriptedBackend(this.response);

  Map<String, dynamic> response;
  int invokeCount = 0;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    invokeCount += 1;
    expect(name, 'completeOnboarding');
    return response;
  }
}

UserProfile _completeDraft({
  String uid = 'u1',
  bool flags = false,
  OnboardingStep step = OnboardingStep.photos,
}) {
  return UserProfile(
    uid: uid,
    displayName: 'Ada',
    birthDate: DateTime(1995, 5, 5),
    gender: 'woman',
    interestedIn: 'men',
    city: 'Istanbul',
    interests: const ['music', 'travel', 'food'],
    education: 'bachelors',
    relationshipGoal: 'long_term',
    lifestyleProfile: const ProfileLifestyle(
      smoking: 'never',
      drinking: 'never',
      exercise: 'regularly',
      pets: 'dog',
    ),
    bio: 'Looking for good conversation and coffee.',
    photos: const [
      ProfilePhoto(id: '1', storagePath: 'a', moderationStatus: 'pending'),
      ProfilePhoto(id: '2', storagePath: 'b', moderationStatus: 'pending'),
      ProfilePhoto(id: '3', storagePath: 'c', moderationStatus: 'pending'),
    ],
    onboardingStep: step,
    profileCompleted: flags,
    onboardingCompleted: flags,
    isProfileComplete: flags,
    isDiscoverable: flags,
  );
}

void main() {
  test(
    'complete trusts callable ok when Firestore re-read still has false flags',
    () async {
      final profiles = FakeProfileRepository();
      final draft = _completeDraft();
      profiles.profiles[draft.uid] = draft;

      final backend = _ScriptedBackend({
        'ok': true,
        'profileCompleted': true,
        'isDiscoverable': true,
        'age': 30,
      });

      final repo = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: backend,
        flagReadRetryDelay: Duration.zero,
      );

      final result = await repo.complete(draft);
      expect(result.isSuccess, isTrue);
      expect(backend.invokeCount, 1);
      final value = (result as Success<UserProfile>).value;
      expect(value.profileCompleted, isTrue);
      expect(value.onboardingCompleted, isTrue);
      expect(value.isProfileComplete, isTrue);
      expect(value.isDiscoverable, isTrue);
    },
  );

  test('complete fails when callable does not confirm and flags stay false', () async {
    final profiles = FakeProfileRepository();
    final draft = _completeDraft();
    profiles.profiles[draft.uid] = draft;

    final backend = _ScriptedBackend({'ok': false});
    final repo = OnboardingRepositoryImpl(
      profiles: profiles,
      backend: backend,
      flagReadRetryDelay: Duration.zero,
    );

    final result = await repo.complete(draft);
    expect(result.isError, isTrue);
    expect(backend.invokeCount, 1);
  });

  test('complete succeeds when re-read eventually shows flags', () async {
    final profiles = FakeProfileRepository();
    final draft = _completeDraft();
    profiles.profiles[draft.uid] = draft;

    final mutatingBackend = _MutatingBackend(
      onInvoke: () {
        profiles.profiles[draft.uid] = draft.copyWith(
          profileCompleted: true,
          onboardingCompleted: true,
          isProfileComplete: true,
          isDiscoverable: true,
          onboardingStep: OnboardingStep.complete,
        );
      },
    );

    final repo = OnboardingRepositoryImpl(
      profiles: profiles,
      backend: mutatingBackend,
      flagReadRetryDelay: Duration.zero,
    );

    final result = await repo.complete(draft);
    expect(result.isSuccess, isTrue);
    expect(mutatingBackend.invokeCount, 1);
    final value = (result as Success<UserProfile>).value;
    expect(value.profileCompleted, isTrue);
  });

  test('initialize keeps celebration step when draft is complete without flags',
      () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final repo = services.onboardingRepository as FakeOnboardingRepository;
    repo.saved = _completeDraft(step: OnboardingStep.complete, flags: false);

    await services.controller.initialize(const AuthUser(id: 'u1'));
    expect(services.controller.step, OnboardingStep.complete);
  });

  test('initialize keeps complete when flags already true', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final repo = services.onboardingRepository as FakeOnboardingRepository;
    repo.saved = _completeDraft(step: OnboardingStep.complete, flags: true);

    await services.controller.initialize(const AuthUser(id: 'u1'));
    expect(services.controller.step, OnboardingStep.complete);
  });

  test('complete() rejects duplicate concurrent calls', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final controller = services.controller;
    final draft = _completeDraft();
    await controller.initialize(const AuthUser(id: 'u1'));
    controller.profile = draft;
    controller.photoDrafts = [
      for (final photo in draft.photos)
        OnboardingPhotoDraft(id: photo.id, remote: photo),
    ];
    controller.step = OnboardingStep.complete;

    final first = controller.complete();
    final second = await controller.complete();
    expect(second.isError, isTrue);
    final firstResult = await first;
    expect(firstResult.isSuccess, isTrue);
  });
}

class _MutatingBackend implements BackendCallable {
  _MutatingBackend({required this.onInvoke});

  final void Function() onInvoke;
  int invokeCount = 0;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    invokeCount += 1;
    onInvoke();
    return {
      'ok': true,
      'profileCompleted': true,
      'isDiscoverable': true,
    };
  }
}
