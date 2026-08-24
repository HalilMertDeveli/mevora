import 'package:mevora/core/di/onboarding_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

import 'fake_profile_repository.dart';

class FakeOnboardingRepository implements OnboardingRepository {
  UserProfile? saved;

  @override
  Future<Result<UserProfile>> complete(UserProfile profile) async {
    final validation = OnboardingValidators.validateCompletion(profile);
    if (validation.isError) {
      return Err((validation as Err<void>).failure);
    }
    saved = profile.copyWith(
      profileCompleted: true,
      onboardingCompleted: true,
      isProfileComplete: true,
      isDiscoverable: true,
    );
    return Success(saved!);
  }

  @override
  Future<UserProfile?> loadDraft(String uid) async => saved;

  @override
  Future<Result<UserProfile>> saveStep({
    required UserProfile profile,
    required OnboardingStep step,
  }) async {
    saved = profile;
    return Success(profile);
  }

  @override
  Stream<UserProfile?> watchDraft(String uid) async* {
    yield saved;
  }
}

class FakeStorageRepository implements StorageRepository {
  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    return Success(Uri.parse('https://example.com/$path'));
  }

  @override
  Future<Result<void>> delete(String path) async => const Success(null);

  @override
  Future<Result<List<int>>> downloadBytes(String path) async =>
      const Success(<int>[]);

  @override
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    return Success(Uri.parse('https://example.com/$ownerUid/$imageId'));
  }

  @override
  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  }) async {
    return const Success(null);
  }
}

OnboardingServices createFakeOnboardingServices() {
  final profiles = FakeProfileRepository();
  final storage = FakeStorageRepository();
  final onboarding = FakeOnboardingRepository();
  const picker = StubProfilePhotoPicker();
  final controller = OnboardingController(
    repository: onboarding,
    storage: storage,
    photoPicker: picker,
  );
  return OnboardingServices(
    profileRepository: profiles,
    storageRepository: storage,
    onboardingRepository: onboarding,
    photoPicker: picker,
    controller: controller,
  );
}
