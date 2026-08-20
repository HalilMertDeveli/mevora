import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/storage/storage_provider.dart';

/// Profile / chat file storage. Implemented by [FirebaseStorageDataSource].
abstract class StorageRepository implements StorageProvider {
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
    void Function(double progress)? onProgress,
  });

  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  });
}
