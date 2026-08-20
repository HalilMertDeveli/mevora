import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';

class OnboardingRepositoryImpl implements OnboardingRepository {
  OnboardingRepositoryImpl({
    required ProfileRepository profiles,
    FirebaseFirestore? firestore,
  }) : _profiles = profiles,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final ProfileRepository _profiles;
  final FirebaseFirestore _firestore;

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
      await _profiles.saveMine(draft);
      return Success(draft);
    } on Object catch (error) {
      return Err(
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
    final completed = _withLifestyleTags(
      profile.copyWith(
        profileCompleted: true,
        onboardingCompleted: true,
        isProfileComplete: true,
        isDiscoverable: true,
        onboardingStep: OnboardingStep.complete,
      ),
    );
    try {
      await _profiles.saveMine(completed);
      await _syncAccountFlags(completed);
      return Success(completed);
    } on Object catch (error) {
      return Err(
        NetworkFailure('Could not complete onboarding.'),
      );
    }
  }

  Future<void> _syncAccountFlags(UserProfile profile) {
    return _firestore.collection(FirestorePaths.users).doc(profile.uid).set(
      {
        'profileCompleted': true,
        'onboardingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
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
