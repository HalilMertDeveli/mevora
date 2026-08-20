import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/data/datasources/firebase_storage_data_source.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

class StorageRepositoryImpl implements StorageRepository {
  StorageRepositoryImpl({required FirebaseStorageDataSource dataSource})
    : _dataSource = dataSource;

  final FirebaseStorageDataSource _dataSource;

  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) {
    return _dataSource.uploadBytes(
      path: path,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  @override
  Future<Result<void>> delete(String path) => _dataSource.delete(path);

  @override
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
    void Function(double progress)? onProgress,
  }) {
    return _dataSource.uploadProfileImage(
      ownerUid: ownerUid,
      imageId: imageId,
      bytes: bytes,
      contentType: contentType,
      thumbnail: thumbnail,
      onProgress: onProgress,
    );
  }

  @override
  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  }) {
    return _dataSource.deleteProfileImage(ownerUid: ownerUid, imageId: imageId);
  }
}
