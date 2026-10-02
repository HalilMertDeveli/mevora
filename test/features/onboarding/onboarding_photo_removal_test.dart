import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/fake_profile_photo_remover.dart';

class _OfflineStorage extends FakeStorageRepository {
  @override
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
    void Function(double progress)? onProgress,
  }) async {
    return const Err(NetworkFailure('offline'));
  }
}

Future<({OnboardingController controller, FakeProfilePhotoRemover remover})>
_onPhotoStep({
  int photos = 3,
  StorageRepository? storage,
  Failure? serverFailure,
}) async {
  final remover = FakeProfilePhotoRemover(failure: serverFailure);
  final controller = OnboardingController(
    repository: FakeOnboardingRepository(),
    storage: storage ?? FakeStorageRepository(),
    photoPicker: StubProfilePhotoPicker(
      next: PickedProfilePhoto(
        bytes: List<int>.filled(32, 7),
        contentType: 'image/jpeg',
      ),
    ),
    photoRemover: remover,
  );
  addTearDown(controller.dispose);
  await controller.initialize(const AuthUser(id: 'user-a'));
  controller.step = OnboardingStep.photos;
  for (var i = 0; i < photos; i += 1) {
    await controller.pickPhoto(fromCamera: false);
    // Photo ids are the pick time in microseconds.
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
  expect(controller.photoDrafts, hasLength(photos));
  return (controller: controller, remover: remover);
}

void main() {
  test('removing an uploaded photo also deletes it on the server', () async {
    final s = await _onPhotoStep();
    final id = s.controller.photoDrafts[1].id;

    s.controller.removePhoto(id);

    expect(s.controller.photoDrafts.map((d) => d.id), isNot(contains(id)));
    expect(s.remover.removed, [id]);
  });

  test(
    'a photo that never reached the server is only dropped locally',
    () async {
      final s = await _onPhotoStep(storage: _OfflineStorage());
      final id = s.controller.photoDrafts.first.id;
      expect(s.controller.photoDrafts.first.remote, isNull);

      s.controller.removePhoto(id);

      expect(s.controller.photoDrafts, hasLength(2));
      expect(s.remover.removed, isEmpty);
    },
  );

  test('the photo leaves the list even when the server call fails', () async {
    final s = await _onPhotoStep(
      serverFailure: const NetworkFailure('offline'),
    );
    final id = s.controller.photoDrafts.last.id;

    s.controller.removePhoto(id);
    await Future<void>.delayed(Duration.zero);

    expect(s.controller.photoDrafts, hasLength(2));
    expect(s.controller.errorMessage, isNull);
    expect(s.remover.removed, [id]);
  });
}
