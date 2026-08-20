import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/profile/data/services/profile_image_pipeline.dart';

class ImagePickerProfilePhotoPicker implements ProfilePhotoPicker {
  ImagePickerProfilePhotoPicker({
    ImagePicker? picker,
    ProfileImagePipeline? pipeline,
  }) : _picker = picker ?? ImagePicker(),
       _pipeline = pipeline ?? const ProfileImagePipeline();

  final ImagePicker _picker;
  final ProfileImagePipeline _pipeline;

  @override
  Future<Result<PickedProfilePhoto>> pickFromCamera() {
    return _pick(ImageSource.camera);
  }

  @override
  Future<Result<PickedProfilePhoto>> pickFromGallery() {
    return _pick(ImageSource.gallery);
  }

  Future<Result<PickedProfilePhoto>> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: ProfileImagePipeline.maxEdgePx.toDouble(),
        maxHeight: ProfileImagePipeline.maxEdgePx.toDouble(),
        imageQuality: 85,
      );
      if (file == null) {
        return const Err(ValidationFailure('No photo selected'));
      }
      final bytes = await file.readAsBytes();
      final contentType = _contentTypeForPath(file.path);
      if (!_pipeline.isAllowedType(contentType) ||
          !_pipeline.isAllowedSize(bytes.length)) {
        return const Err(
          ValidationFailure('That image type or size is not allowed.'),
        );
      }
      return Success(
        PickedProfilePhoto(bytes: bytes, contentType: contentType),
      );
    } on Object catch (error) {
      return Err(
        const ValidationFailure('Could not pick that photo.'),
      );
    }
  }

  String _contentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}

class FakeProfilePhotoPicker implements ProfilePhotoPicker {
  FakeProfilePhotoPicker({this.nextBytes});

  List<int>? nextBytes;

  @override
  Future<Result<PickedProfilePhoto>> pickFromCamera() async {
    return _result();
  }

  @override
  Future<Result<PickedProfilePhoto>> pickFromGallery() async {
    return _result();
  }

  Future<Result<PickedProfilePhoto>> _result() async {
    final bytes = nextBytes ?? Uint8List.fromList([1, 2, 3, 4]);
    return Success(
      PickedProfilePhoto(bytes: bytes, contentType: 'image/jpeg'),
    );
  }
}
