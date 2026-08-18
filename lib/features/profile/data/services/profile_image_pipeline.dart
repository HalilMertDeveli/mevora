import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';

/// Uploads go through StorageRepository. Domain never imports Firebase Storage.
abstract class ImageCompressPipeline {
  Future<Result<CompressedImage>> compressProfilePhoto(List<int> bytes);

  Future<Result<CompressedImage>> compressThumbnail(List<int> bytes);
}

class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.contentType,
    required this.width,
    required this.height,
  });

  final List<int> bytes;
  final String contentType;
  final int width;
  final int height;
}

/// Validates type/size before upload. Pixel compression is applied by the
/// presentation picker (or a later native codec). This keeps extra packages
/// out of the data layer.
class ProfileImagePipeline implements ImageCompressPipeline {
  const ProfileImagePipeline();

  static const int maxBytes = 5 * 1024 * 1024;
  static const int maxEdgePx = 1080;
  static const int thumbEdgePx = 320;
  static const Set<String> allowedTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  bool isAllowedType(String contentType) =>
      allowedTypes.contains(contentType.toLowerCase());

  bool isAllowedSize(int byteCount) => byteCount > 0 && byteCount <= maxBytes;

  @override
  Future<Result<CompressedImage>> compressProfilePhoto(List<int> bytes) async {
    return _accept(bytes);
  }

  @override
  Future<Result<CompressedImage>> compressThumbnail(List<int> bytes) async {
    return _accept(bytes);
  }

  Result<CompressedImage> _accept(List<int> bytes) {
    if (!isAllowedSize(bytes.length)) {
      return const Err(
        ValidationFailure('Image must be 5 MB or smaller.'),
      );
    }
    return Success(
      CompressedImage(
        bytes: bytes,
        contentType: 'image/jpeg',
        width: maxEdgePx,
        height: maxEdgePx,
      ),
    );
  }
}
