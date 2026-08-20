import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';

class PickedProfilePhoto {
  const PickedProfilePhoto({
    required this.bytes,
    required this.contentType,
  });

  final List<int> bytes;
  final String contentType;
}

/// Picks profile photos from camera or gallery after permissions are granted.
abstract class ProfilePhotoPicker {
  Future<Result<PickedProfilePhoto>> pickFromGallery();

  Future<Result<PickedProfilePhoto>> pickFromCamera();
}

class StubProfilePhotoPicker implements ProfilePhotoPicker {
  const StubProfilePhotoPicker({this.next});

  final PickedProfilePhoto? next;

  @override
  Future<Result<PickedProfilePhoto>> pickFromCamera() async {
    if (next == null) {
      return const Err(ValidationFailure('No photo selected'));
    }
    return Success(next!);
  }

  @override
  Future<Result<PickedProfilePhoto>> pickFromGallery() async {
    return pickFromCamera();
  }
}
