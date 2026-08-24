import 'package:mevora/core/errors/result.dart';

/// File storage port. Profile photos and chat images go through this,
/// never through Firebase Storage types in UI or domain.
abstract class StorageProvider {
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  });

  Future<Result<List<int>>> downloadBytes(String path);

  Future<Result<void>> delete(String path);
}
