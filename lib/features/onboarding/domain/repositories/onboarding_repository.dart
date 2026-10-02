import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract class OnboardingRepository {
  Future<UserProfile?> loadDraft(String uid);

  /// The member's private surname, kept on their account and never on the
  /// public profile. Null until they have saved one.
  Future<String?> loadLastName(String uid);

  Stream<UserProfile?> watchDraft(String uid);

  /// [requireFaceAnchor]: the server requires this member to have a verified
  /// Face Anchor photo. Checked here to fail early; the server enforces it.
  Future<Result<UserProfile>> saveStep({
    required UserProfile profile,
    required OnboardingStep step,
    required String? lastName,
    bool requireFaceAnchor = false,
  });

  Future<Result<UserProfile>> complete(
    UserProfile profile, {
    required String? lastName,
    bool requireFaceAnchor = false,
  });
}
