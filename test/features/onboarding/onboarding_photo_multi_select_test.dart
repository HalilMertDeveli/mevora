import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';

import 'package:mevora/core/di/onboarding_services_factory.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

import '../../helpers/fake_onboarding_services.dart';

/// Storage that fails every upload after the first [succeedFirst] calls, so a
/// partially failing batch can be exercised.
class _FlakyStorage extends FakeStorageRepository {
  _FlakyStorage({required this.succeedFirst});

  final int succeedFirst;
  int calls = 0;

  @override
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
    void Function(double progress)? onProgress,
  }) async {
    calls += 1;
    if (calls > succeedFirst) {
      return const Err(NetworkFailure('upload failed'));
    }
    return super.uploadProfileImage(
      ownerUid: ownerUid,
      imageId: imageId,
      bytes: bytes,
      contentType: contentType,
      thumbnail: thumbnail,
      onProgress: onProgress,
    );
  }
}

/// Picker that returns a scripted batch, like one Android Photo Picker
/// confirmation with several images ticked.
class _BatchPicker implements ProfilePhotoPicker {
  _BatchPicker({this.count = 3, this.failure});

  int count;
  Failure? failure;
  int? lastLimit;
  int calls = 0;

  @override
  Future<Result<List<PickedProfilePhoto>>> pickMultipleFromGallery({
    required int limit,
  }) async {
    calls += 1;
    lastLimit = limit;
    final error = failure;
    if (error != null) {
      return Err(error);
    }
    return Success([
      for (var i = 0; i < count; i += 1)
        PickedProfilePhoto(
          bytes: List<int>.filled(32, i + 1),
          contentType: 'image/jpeg',
        ),
    ]);
  }

  @override
  Future<Result<PickedProfilePhoto>> pickFromCamera() async =>
      const Err(ValidationFailure('unused'));

  @override
  Future<Result<PickedProfilePhoto>> pickFromGallery() async =>
      const Err(ValidationFailure('unused'));
}

Future<OnboardingController> _controllerWith(
  ProfilePhotoPicker picker,
  OnboardingServices services, {
  StorageRepository? storage,
}) async {
  final controller = OnboardingController(
    repository: services.onboardingRepository,
    storage: storage ?? services.storageRepository,
    photoPicker: picker,
  );
  await controller.initialize(const AuthUser(id: 'user-a'));
  controller.step = OnboardingStep.photos;
  return controller;
}

void main() {
  test('selecting one image adds one draft', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final picker = _BatchPicker(count: 1);
    final controller = await _controllerWith(picker, services);
    addTearDown(controller.dispose);

    final result = await controller.pickGalleryPhotos();

    expect(result.isSuccess, isTrue);
    expect(controller.photoDrafts, hasLength(1));
  });

  test('selecting three images adds and uploads all three', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final picker = _BatchPicker(count: 3);
    final controller = await _controllerWith(picker, services);
    addTearDown(controller.dispose);

    final result = await controller.pickGalleryPhotos();

    expect(result.isSuccess, isTrue);
    expect(
      controller.photoDrafts,
      hasLength(3),
      reason: 'all three selections must enter the pipeline, not just the first',
    );
    expect(picker.calls, 1, reason: 'one picker interaction, not three');
    expect(
      controller.photoDrafts.map((d) => d.id).toSet(),
      hasLength(3),
      reason: 'batch drafts must not collide on the same id',
    );
    expect(
      controller.photoDrafts.every((d) => d.remote != null),
      isTrue,
      reason: 'each draft must be uploaded',
    );
    expect(controller.canContinuePhotos, isTrue);
  });

  test('uploads go to the per-user pending path, never to public storage', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final controller = await _controllerWith(_BatchPicker(count: 3), services);
    addTearDown(controller.dispose);

    await controller.pickGalleryPhotos();

    for (final draft in controller.photoDrafts) {
      expect(
        draft.remote?.storagePath,
        'users/user-a/profile/pending/${draft.id}.jpg',
        reason: 'moderation path must be unchanged',
      );
    }
  });

  test('a selection larger than the remaining slots is capped', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final picker = _BatchPicker(count: OnboardingConfig.maxPhotos + 4);
    final controller = await _controllerWith(picker, services);
    addTearDown(controller.dispose);

    await controller.pickGalleryPhotos();

    expect(picker.lastLimit, OnboardingConfig.maxPhotos);
    expect(controller.photoDrafts, hasLength(OnboardingConfig.maxPhotos));
  });

  test('the limit shrinks as slots fill and refuses once full', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final picker = _BatchPicker(count: 2);
    final controller = await _controllerWith(picker, services);
    addTearDown(controller.dispose);

    await controller.pickGalleryPhotos();
    expect(picker.lastLimit, OnboardingConfig.maxPhotos);

    await controller.pickGalleryPhotos();
    expect(picker.lastLimit, OnboardingConfig.maxPhotos - 2);

    picker.count = OnboardingConfig.maxPhotos;
    await controller.pickGalleryPhotos();
    expect(controller.photoDrafts, hasLength(OnboardingConfig.maxPhotos));

    final full = await controller.pickGalleryPhotos();
    expect(full.isError, isTrue, reason: 'no room left');
  });

  test('one failed upload does not discard the other selections', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final controller = await _controllerWith(
      _BatchPicker(count: 3),
      services,
      storage: _FlakyStorage(succeedFirst: 1),
    );
    addTearDown(controller.dispose);

    final result = await controller.pickGalleryPhotos();

    expect(result.isError, isTrue, reason: 'the failure is surfaced');
    expect(
      controller.photoDrafts,
      hasLength(3),
      reason: 'every selection is still tracked so the user can retry',
    );
    expect(
      controller.photoDrafts.where((d) => d.remote != null),
      isNotEmpty,
      reason: 'the successful uploads are kept',
    );
  });

  test('a cancelled picker surfaces the error and adds nothing', () async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final picker = _BatchPicker()
      ..failure = const ValidationFailure('No photo selected');
    final controller = await _controllerWith(picker, services);
    addTearDown(controller.dispose);

    final result = await controller.pickGalleryPhotos();

    expect(result.isError, isTrue);
    expect(controller.photoDrafts, isEmpty);
  });
}
