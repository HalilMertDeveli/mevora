import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';

class CompleteOnboarding {
  const CompleteOnboarding(this._profiles);

  final ProfileRepository _profiles;

  Future<Result<UserProfile>> call(UserProfile profile) async {
    if (profile.resolvedAge < AppConstants.minimumAge) {
      return const Err(
        ValidationFailure('You must be 18 or older to use Mevora.'),
      );
    }
    if (profile.displayName.trim().isEmpty) {
      return const Err(ValidationFailure('First name is required'));
    }
    if (profile.photos.where((photo) => photo.isPublic || photo.moderationStatus == 'pending').isEmpty) {
      return const Err(ValidationFailure('Add at least one photo'));
    }
    final completed = profile.copyWith(
      profileCompleted: true,
      onboardingCompleted: true,
      isDiscoverable: true,
    );
    await _profiles.saveMine(completed);
    return Success(completed);
  }
}
