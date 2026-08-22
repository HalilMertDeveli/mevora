import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';

import '../../helpers/fake_onboarding_services.dart';

void main() {
  test('picking a photo uploads immediately and records remote metadata', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final picker = StubProfilePhotoPicker(
      next: PickedProfilePhoto(
        bytes: List<int>.filled(32, 7),
        contentType: 'image/jpeg',
      ),
    );
    final controller = OnboardingController(
      repository: services.onboardingRepository,
      storage: services.storageRepository,
      photoPicker: picker,
    );
    addTearDown(controller.dispose);

    await controller.initialize(const AuthUser(id: 'user-a'));
    controller.step = OnboardingStep.photos;

    final result = await controller.pickPhoto(fromCamera: false);
    expect(result.isSuccess, isTrue);
    expect(controller.photoDrafts, hasLength(1));
    expect(controller.photoDrafts.first.isUploading, isFalse);
    expect(controller.photoDrafts.first.remote?.downloadUrl, isNotNull);
    expect(
      controller.photoDrafts.first.remote?.storagePath,
      'users/user-a/profile/pending/${controller.photoDrafts.first.id}.jpg',
    );
    expect(controller.canContinuePhotos, isFalse);
  });

  test('continue stays disabled until three successful uploads', () async {
    final services = createFakeOnboardingServices();
    final picker = StubProfilePhotoPicker(
      next: PickedProfilePhoto(
        bytes: List<int>.filled(32, 3),
        contentType: 'image/jpeg',
      ),
    );
    final controller = OnboardingController(
      repository: services.onboardingRepository,
      storage: services.storageRepository,
      photoPicker: picker,
    );
    addTearDown(controller.dispose);
    await controller.initialize(const AuthUser(id: 'user-a'));
    controller.step = OnboardingStep.photos;

    await controller.pickPhoto(fromCamera: false);
    await controller.pickPhoto(fromCamera: false);
    expect(controller.canContinuePhotos, isFalse);
    await controller.pickPhoto(fromCamera: false);
    expect(controller.canContinuePhotos, isTrue);
    expect(controller.photoDrafts.every((d) => d.remote != null), isTrue);
  });

  test('min photos message is Turkish', () {
    expect(PhotoUploadMessages.minRequired, contains('3'));
  });
}
