import 'package:mevora/core/errors/result.dart';

class CapturedSelfie {
  const CapturedSelfie({required this.bytes, required this.contentType});

  final List<int> bytes;
  final String contentType;
}

/// Takes a fresh photo of the member with the camera.
///
/// There is deliberately no way to supply an existing image through this
/// port: a verification selfie is captured now, never picked from the gallery.
/// It is temporary verification media and is never added to the profile.
abstract class LiveSelfieCapture {
  /// A null value means the member closed the camera without taking a photo.
  Future<Result<CapturedSelfie?>> capture();
}
