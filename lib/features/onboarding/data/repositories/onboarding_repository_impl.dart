import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';

class OnboardingRepositoryImpl implements OnboardingRepository {
  OnboardingRepositoryImpl({
    required ProfileRepository profiles,
    required BackendCallable backend,
  }) : _profiles = profiles,
       _backend = backend;

  final ProfileRepository _profiles;
  final BackendCallable _backend;

  @override
  Future<UserProfile?> loadDraft(String uid) => _profiles.getById(uid);

  @override
  Stream<UserProfile?> watchDraft(String uid) => _profiles.watchById(uid);

  @override
  Future<Result<UserProfile>> saveStep({
    required UserProfile profile,
    required OnboardingStep step,
  }) async {
    final validation = OnboardingValidators.validateStep(step, profile);
    if (validation.isError) {
      return Err((validation as Err<void>).failure);
    }
    final nextStep = step.next ?? step;
    final draft = _withLifestyleTags(
      profile.copyWith(onboardingStep: nextStep),
    );
    try {
      await _profiles.saveMine(_clientSafeDraft(draft));
      return Success(draft);
    } on Object {
      return const Err(
        NetworkFailure('Could not save onboarding progress.'),
      );
    }
  }

  @override
  Future<Result<UserProfile>> complete(UserProfile profile) async {
    final validation = OnboardingValidators.validateCompletion(profile);
    if (validation.isError) {
      return Err((validation as Err<void>).failure);
    }
    final draft = _withLifestyleTags(
      profile.copyWith(
        onboardingStep: OnboardingStep.complete,
      ),
    );
    try {
      await _profiles.saveMine(_clientSafeDraft(draft));
      await _backend.invoke('completeOnboarding');
      final completed = await _profiles.getById(profile.uid);
      if (completed == null || !completed.isDiscoverable) {
        return const Err(
          NetworkFailure('Could not complete onboarding.'),
        );
      }
      return Success(completed);
    } on Object {
      return const Err(
        NetworkFailure('Could not complete onboarding.'),
      );
    }
  }

  UserProfile _clientSafeDraft(UserProfile profile) {
    return profile.copyWith(
      profileCompleted: false,
      onboardingCompleted: false,
      isProfileComplete: false,
      isDiscoverable: false,
    );
  }

  UserProfile _withLifestyleTags(UserProfile profile) {
    final tags = profile.lifestyleProfile.toTags();
    if (tags.isEmpty) {
      return profile;
    }
    return profile.copyWith(lifestyle: tags);
  }
}
