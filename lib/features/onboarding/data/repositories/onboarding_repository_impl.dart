import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';
import 'package:mevora/features/profile/domain/validators/person_name_validator.dart';

class OnboardingRepositoryImpl implements OnboardingRepository {
  OnboardingRepositoryImpl({
    required ProfileRepository profiles,
    required BackendCallable backend,
  }) : _profiles = profiles,
       _backend = backend;

  final ProfileRepository _profiles;
  final BackendCallable _backend;
  static const _onboardingCallableName = 'completeOnboarding';

  @override
  Future<UserProfile?> loadDraft(String uid) => _profiles.getById(uid);

  @override
  Future<String?> loadLastName(String uid) => _profiles.loadMyLastName(uid);

  @override
  Stream<UserProfile?> watchDraft(String uid) => _profiles.watchById(uid);

  @override
  Future<Result<UserProfile>> saveStep({
    required UserProfile profile,
    required OnboardingStep step,
    required String? lastName,
    bool requireFaceAnchor = false,
  }) async {
    final validation = OnboardingValidators.validateStep(
      step,
      profile,
      lastName: lastName,
      requireFaceAnchor: requireFaceAnchor,
    );
    if (validation.isError) {
      return Err((validation as Err<void>).failure);
    }
    final nextStep = step.next ?? step;
    final draft = _withLifestyleTags(
      profile.copyWith(
        displayName: PersonNameValidator.normalize(profile.displayName),
        onboardingStep: nextStep,
      ),
    );
    try {
      // The surname goes to the private account document, on the step that
      // collects it. The public profile below never carries it.
      if (step == OnboardingStep.basicInfo) {
        await _profiles.saveMyLastName(profile.uid, lastName!);
      }
      await _profiles.saveMine(_clientSafeDraft(draft));
      return Success(draft);
    } on Object {
      return const Err(
        NetworkFailure('Could not save onboarding progress.'),
      );
    }
  }

  @override
  Future<Result<UserProfile>> complete(
    UserProfile profile, {
    required String? lastName,
    bool requireFaceAnchor = false,
  }) async {
    final validation = OnboardingValidators.validateCompletion(
      profile,
      lastName: lastName,
      requireFaceAnchor: requireFaceAnchor,
    );
    if (validation.isError) {
      return Err((validation as Err<void>).failure);
    }
    final draft = _withLifestyleTags(
      profile.copyWith(
        displayName: PersonNameValidator.normalize(profile.displayName),
        onboardingStep: OnboardingStep.complete,
      ),
    );
    try {
      // Merge server-side moderation statuses so we never overwrite an already
      // approved photo back to pending right before completeOnboarding.
      final merged = await _mergeRemotePhotoStatuses(draft);
      await _profiles.saveMine(_clientSafeDraft(merged));
      final response = await _backend.invoke(_onboardingCallableName);
      final completed = await _profiles.getById(profile.uid);
      final finished = completed != null &&
          (completed.onboardingCompleted ||
              completed.profileCompleted ||
              completed.isProfileComplete);
      if (!finished) {
        return Err(
          NetworkFailure(
            kDebugMode
                ? 'Could not complete onboarding (flags missing). '
                    'uid=${profile.uid} responseKeys=${response.keys.toList()} '
                    'onboardingCompleted=${completed?.onboardingCompleted} '
                    'isDiscoverable=${completed?.isDiscoverable}'
                : 'Could not complete onboarding.',
          ),
        );
      }
      return Success(completed);
    } on FirebaseFunctionsException catch (error) {
      return Err(NetworkFailure(_mapFunctionsError(error)));
    } on Object catch (error) {
      return Err(
        NetworkFailure(
          kDebugMode
              ? 'Could not complete onboarding: $error'
              : 'Could not complete onboarding.',
        ),
      );
    }
  }

  Future<UserProfile> _mergeRemotePhotoStatuses(UserProfile draft) async {
    final remote = await _profiles.getById(draft.uid);
    if (remote == null || remote.photos.isEmpty || draft.photos.isEmpty) {
      return draft;
    }
    final byId = {
      for (final photo in remote.photos) photo.id: photo,
    };
    final merged = draft.photos.map((photo) {
      final server = byId[photo.id];
      if (server == null) {
        return photo;
      }
      final status = server.moderationStatus;
      if (status == 'approved' ||
          status == 'rejected' ||
          status == 'manual_review') {
        // The verified flag travels with the status it depends on. Both are
        // re-imposed by the server either way.
        return photo.copyWith(
          moderationStatus: status,
          isFaceAnchorVerified: server.isFaceAnchorVerified,
        );
      }
      return photo;
    }).toList(growable: false);
    return draft.copyWith(photos: merged);
  }

  static String _mapFunctionsError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'failed-precondition':
        final details = error.message ?? '';
        if (details.contains('photos-required')) {
          return OnboardingMessages.serverPhotosRequired;
        }
        if (details.contains('face-anchor-required')) {
          return OnboardingMessages.faceAnchorRequired;
        }
        if (details.contains('photos-not-approved')) {
          return OnboardingMessages.serverPhotosInReview;
        }
        if (details.contains('interests-required')) {
          return OnboardingMessages.serverInterestsRequired;
        }
        if (details.contains('underage')) {
          return OnboardingMessages.underage;
        }
        if (details.contains('first-name-required')) {
          return OnboardingMessages.firstNameRequired;
        }
        if (details.contains('first-name-too-long')) {
          return OnboardingMessages.firstNameTooLong;
        }
        if (details.contains('last-name-required')) {
          return OnboardingMessages.lastNameRequired;
        }
        if (details.contains('last-name-too-long')) {
          return OnboardingMessages.lastNameTooLong;
        }
        if (details.contains('smoking-required') ||
            details.contains('drinking-required') ||
            details.contains('exercise-required') ||
            details.contains('pets-required')) {
          return OnboardingMessages.serverLifestyleRequired;
        }
        if (details.contains('profile-missing')) {
          return OnboardingMessages.serverProfileMissing;
        }
        return kDebugMode
            ? 'Could not complete onboarding (${error.message}).'
            : 'Could not complete onboarding.';
      case 'unauthenticated':
        return OnboardingMessages.serverSignInAgain;
      case 'permission-denied':
        return OnboardingMessages.serverNotAllowed;
      default:
        return kDebugMode
            ? 'Could not complete onboarding (${error.code}: ${error.message}).'
            : 'Could not complete onboarding.';
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
