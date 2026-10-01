import 'package:image_picker/image_picker.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/face_anchor/domain/face_anchor_messages.dart';
import 'package:mevora/features/face_anchor/domain/services/live_selfie_capture.dart';
import 'package:mevora/features/profile/data/services/profile_image_pipeline.dart';

/// Captures the verification selfie with the device camera.
///
/// Only `ImageSource.camera` is ever requested — this class has no gallery
/// path — and the front camera is asked for. (Android treats that as a
/// preference: some camera apps open on the rear lens and the member switches.)
class ImagePickerLiveSelfieCapture implements LiveSelfieCapture {
  ImagePickerLiveSelfieCapture({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Result<CapturedSelfie?>> capture() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: ProfileImagePipeline.maxEdgePx.toDouble(),
        maxHeight: ProfileImagePipeline.maxEdgePx.toDouble(),
        // Re-encoded as JPEG by the picker, which also drops the EXIF block.
        imageQuality: 88,
      );
      if (file == null) {
        return const Success(null);
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > ProfileImagePipeline.maxBytes) {
        return const Err(ValidationFailure(FaceAnchorMessages.captureFailed));
      }
      final lower = file.path.toLowerCase();
      final contentType = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
      return Success(CapturedSelfie(bytes: bytes, contentType: contentType));
    } on Object catch (error) {
      final denied = error.toString().contains('camera_access_denied');
      return Err(
        ValidationFailure(
          denied
              ? FaceAnchorMessages.cameraDenied
              : FaceAnchorMessages.captureFailed,
        ),
      );
    }
  }
}
