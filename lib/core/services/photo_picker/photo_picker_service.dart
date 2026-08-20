class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    this.contentType = 'image/jpeg',
  });

  final List<int> bytes;
  final String contentType;
}

/// Picks profile photos after permissions are granted.
abstract class PhotoPickerService {
  Future<PickedPhoto?> pickFromGallery();

  Future<PickedPhoto?> pickFromCamera();
}
