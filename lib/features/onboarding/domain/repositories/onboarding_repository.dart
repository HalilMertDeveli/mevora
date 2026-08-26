import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract class OnboardingRepository {
  Future<UserProfile?> loadDraft(String uid);

  Stream<UserProfile?> watchDraft(String uid);

  Future<Result<UserProfile>> saveStep({
    required UserProfile profile,
    required OnboardingStep step,
  });

  Future<Result<UserProfile>> complete(UserProfile profile);
}
