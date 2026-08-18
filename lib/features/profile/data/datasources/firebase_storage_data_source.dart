import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/data/services/profile_image_pipeline.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

class FirebaseStorageDataSource implements StorageRepository {
  FirebaseStorageDataSource({
    FirebaseStorage? storage,
    this.pipeline = const ProfileImagePipeline(),
  }) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final ProfileImagePipeline pipeline;

  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    if (!pipeline.isAllowedType(contentType) || !pipeline.isAllowedSize(bytes.length)) {
      return const Err(
        ValidationFailure('That image type or size is not allowed.'),
      );
    }
    try {
      final ref = _storage.ref(path);
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: contentType),
      );
      final url = await ref.getDownloadURL();
      return Success(Uri.parse(url));
    } on Object catch (error) {
      return Err(
        FailureMapper.from(
          NetworkException('Could not upload that file.', cause: error),
        ),
      );
    }
  }

  @override
  Future<Result<void>> delete(String path) async {
    try {
      await _storage.ref(path).delete();
      return const Success(null);
    } on Object catch (error) {
      return Err(
        FailureMapper.from(
          NetworkException('Could not delete that file.', cause: error),
        ),
      );
    }
  }

  @override
  Future<Result<Uri>> uploadProfileImage({
    required String ownerUid,
    required String imageId,
    required List<int> bytes,
    required String contentType,
    bool thumbnail = false,
  }) {
    final path = thumbnail
        ? StoragePaths.profileThumb(ownerUid: ownerUid, imageId: imageId)
        : StoragePaths.profilePending(ownerUid: ownerUid, imageId: imageId);
    return uploadBytes(path: path, bytes: bytes, contentType: contentType);
  }

  @override
  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  }) async {
    final pending = await delete(
      StoragePaths.profilePending(ownerUid: ownerUid, imageId: imageId),
    );
    if (pending.isError) {
      return pending;
    }
    await delete(
      StoragePaths.profileApproved(ownerUid: ownerUid, imageId: imageId),
    );
    return delete(
      StoragePaths.profileThumb(ownerUid: ownerUid, imageId: imageId),
    );
  }
}
