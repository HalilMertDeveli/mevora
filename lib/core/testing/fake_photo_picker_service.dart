import 'package:mevora/core/services/photo_picker/photo_picker_service.dart';

/// Test/dev photo picker that returns predetermined bytes.
class FakePhotoPickerService implements PhotoPickerService {
  FakePhotoPickerService({this.nextPhoto});

  PickedPhoto? nextPhoto;
  int galleryCalls = 0;
  int cameraCalls = 0;

  @override
  Future<PickedPhoto?> pickFromGallery() async {
    galleryCalls += 1;
    return nextPhoto;
  }

  @override
  Future<PickedPhoto?> pickFromCamera() async {
    cameraCalls += 1;
    return nextPhoto;
  }
}

/// Production fallback when no native picker is configured.
class NoOpPhotoPickerService implements PhotoPickerService {
  const NoOpPhotoPickerService();

  @override
  Future<PickedPhoto?> pickFromGallery() async => null;

  @override
  Future<PickedPhoto?> pickFromCamera() async => null;
}
