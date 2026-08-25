import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
import 'package:flutter/foundation.dart';
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
  static const _onboardingCallableName = 'completeOnboarding';

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
        return photo.copyWith(moderationStatus: status);
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
          return 'Add at least 3 photos to finish onboarding.';
        }
        if (details.contains('photos-not-approved')) {
          return 'Photos are still under review. Please try again shortly.';
        }
        if (details.contains('interests-required')) {
          return 'Pick at least 3 interests to continue.';
        }
        if (details.contains('underage')) {
          return 'You must be 18 or older to use Mevora.';
        }
        if (details.contains('smoking-required') ||
            details.contains('drinking-required') ||
            details.contains('exercise-required') ||
            details.contains('pets-required')) {
          return 'Complete lifestyle answers to finish onboarding.';
        }
        if (details.contains('profile-missing')) {
          return 'Profile is incomplete. Please go back and fill required fields.';
        }
        return kDebugMode
            ? 'Could not complete onboarding (${error.message}).'
            : 'Could not complete onboarding.';
      case 'unauthenticated':
        return 'Please sign in again to finish onboarding.';
      case 'permission-denied':
        return 'This account cannot complete onboarding.';
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
