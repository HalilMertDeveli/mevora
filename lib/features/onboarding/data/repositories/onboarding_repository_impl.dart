import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
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
  static const _functionsRegion = 'europe-west1';

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
      // #region agent log
      _writeDebugLog(
        runId: 'onboarding-complete',
        hypothesisId: 'H1',
        location: 'onboarding_repository_impl.dart:complete:before_callable',
        message: 'calling_complete_onboarding',
        data: <String, Object?>{
          'uid': profile.uid,
          'callable': _onboardingCallableName,
          'region': _functionsRegion,
        },
      );
      // #endregion
      await _profiles.saveMine(_clientSafeDraft(draft));
      final response = await _backend.invoke(_onboardingCallableName);
      // #region agent log
      _writeDebugLog(
        runId: 'onboarding-complete',
        hypothesisId: 'H1',
        location: 'onboarding_repository_impl.dart:complete:after_callable',
        message: 'complete_onboarding_response',
        data: <String, Object?>{
          'uid': profile.uid,
          'keys': response.keys.toList(growable: false),
          'ok': response['ok'],
          'profileCompleted': response['profileCompleted'],
          'isDiscoverable': response['isDiscoverable'],
        },
      );
      // #endregion
      final completed = await _profiles.getById(profile.uid);
      if (completed == null || !completed.isDiscoverable) {
        return Err(
          NetworkFailure(
            kDebugMode
                ? 'Could not complete onboarding (discoverable check failed). uid=${profile.uid} completedNull=${completed == null} isDiscoverable=${completed?.isDiscoverable}'
                : 'Could not complete onboarding.',
          ),
        );
      }
      return Success(completed);
    } on Object catch (error) {
      // #region agent log
      _writeDebugLog(
        runId: 'onboarding-complete',
        hypothesisId: 'H1',
        location: 'onboarding_repository_impl.dart:complete:error',
        message: 'complete_onboarding_failed',
        data: <String, Object?>{
          'uid': profile.uid,
          'callable': _onboardingCallableName,
          'region': _functionsRegion,
          'error': error.toString(),
        },
      );
      // #endregion
      return Err(
        NetworkFailure(
          kDebugMode
              ? 'Could not complete onboarding (backend/storage error): $error'
              : 'Could not complete onboarding.',
        ),
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

  void _writeDebugLog({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, Object?> data,
  }) {
    try {
      final entry = <String, Object?>{
        'sessionId': '80971b',
        'runId': runId,
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      File('D:/debug-80971b.log').writeAsStringSync(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
      );
    } on Object {
      // Ignore logging failures in runtime path.
    }
  }
}
