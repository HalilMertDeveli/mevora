import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';
import 'package:mevora/features/profile/data/services/profile_image_pipeline.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

class FirebaseStorageDataSource implements StorageRepository {
  FirebaseStorageDataSource({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    this.pipeline = const ProfileImagePipeline(),
  }) : _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance;

  static const Duration _uploadTimeout = Duration(seconds: 45);

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final ProfileImagePipeline pipeline;

  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      _logError('no currentUser', code: 'unauthenticated', path: path);
      return const Err(ValidationFailure(PhotoUploadMessages.needSignIn));
    }
    if (!path.startsWith('users/${user.uid}/')) {
      _logError(
        'path does not match auth uid',
        code: 'unauthorized',
        path: path,
      );
      return const Err(ValidationFailure(PhotoUploadMessages.failed));
    }
    if (!_isAllowedUpload(path: path, contentType: contentType, size: bytes.length)) {
      _logError(
        'rejected contentType=$contentType size=${bytes.length}',
        code: 'invalid-argument',
        path: path,
      );
      return const Err(ValidationFailure(PhotoUploadMessages.invalidFile));
    }

    _log(
      'Upload Started uid=${user.uid} size=${bytes.length} '
      'contentType=$contentType path=$path',
      path: path,
    );
    UploadTask? task;
    StreamSubscription<TaskSnapshot>? subscription;
    try {
      final ref = _storage.ref(path);
      task = ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: contentType),
      );
      subscription = task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes <= 0) {
          return;
        }
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress.clamp(0, 1));
        _log(
          'Upload Progress ${(progress * 100).round()}% state=${snapshot.state.name}',
          path: path,
        );
      });
      await task.timeout(_uploadTimeout);
      onProgress?.call(1);
      final url = await ref.getDownloadURL().timeout(
        const Duration(seconds: 15),
      );
      _log('Upload Completed downloadUrlHost=${Uri.tryParse(url)?.host}', path: path);
      return Success(Uri.parse(url));
    } on TimeoutException {
      await _cancel(task);
      _logError('timeout after ${_uploadTimeout.inSeconds}s', code: 'timeout', path: path);
      return const Err(NetworkFailure(PhotoUploadMessages.timeout));
    } on FirebaseException catch (error) {
      _logError(error.message ?? error.code, code: error.code, path: path);
      final isChat = path.contains('/chat/');
      return Err(
        NetworkFailure(
          isChat ? ChatStrings.mediaUploadFailed : PhotoUploadMessages.failed,
        ),
      );
    } on Object catch (error) {
      _logError('$error', code: 'unknown', path: path);
      return Err(
        FailureMapper.from(
          NetworkException(PhotoUploadMessages.failed, cause: error),
        ),
      );
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<Result<void>> delete(String path) async {
    try {
      await _storage.ref(path).delete();
      return const Success(null);
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return const Success(null);
      }
      return const Err(NetworkFailure(PhotoUploadMessages.failed));
    } on Object catch (error) {
      return Err(
        FailureMapper.from(
          NetworkException(PhotoUploadMessages.failed, cause: error),
        ),
      );
    }
  }

  @override
  Future<Result<List<int>>> downloadBytes(String path) async {
    try {
      final data = await _storage.ref(path).getData();
      if (data == null) {
        return const Err(NetworkFailure(PhotoUploadMessages.failed));
      }
      return Success(data);
    } on FirebaseException catch (error) {
      _logError(error.message ?? error.code, code: error.code, path: path);
      return const Err(NetworkFailure(PhotoUploadMessages.failed));
    } on Object catch (error) {
      _logError('$error', code: 'unknown', path: path);
      return Err(
        FailureMapper.from(
          NetworkException(PhotoUploadMessages.failed, cause: error),
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
    void Function(double progress)? onProgress,
  }) {
    final path = thumbnail
        ? StoragePaths.profileThumb(ownerUid: ownerUid, imageId: imageId)
        : StoragePaths.profilePending(
            ownerUid: ownerUid,
            imageId: imageId,
            extension: _extensionFor(contentType),
          );
    return uploadBytes(
      path: path,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  @override
  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  }) async {
    final paths = [
      StoragePaths.profilePhoto(ownerUid: ownerUid, imageId: imageId),
      StoragePaths.profilePhoto(
        ownerUid: ownerUid,
        imageId: imageId,
        extension: 'png',
      ),
      StoragePaths.profilePhoto(
        ownerUid: ownerUid,
        imageId: imageId,
        extension: 'webp',
      ),
      StoragePaths.profilePending(
        ownerUid: ownerUid,
        imageId: imageId,
        extension: 'jpg',
      ),
      StoragePaths.profilePending(
        ownerUid: ownerUid,
        imageId: imageId,
        extension: 'png',
      ),
      StoragePaths.profilePending(
        ownerUid: ownerUid,
        imageId: imageId,
        extension: 'webp',
      ),
      StoragePaths.profileApproved(ownerUid: ownerUid, imageId: imageId),
      StoragePaths.profileThumb(ownerUid: ownerUid, imageId: imageId),
    ];
    for (final path in paths) {
      final result = await delete(path);
      if (result.isError) {
        return result;
      }
    }
    return const Success(null);
  }

  bool _isAllowedUpload({
    required String path,
    required String contentType,
    required int size,
  }) {
    final isChat = path.contains('/chat/');
    if (isChat) {
      return StoragePaths.isAllowedChatUpload(
        contentType: contentType,
        sizeBytes: size,
      );
    }
    return pipeline.isAllowedType(contentType) && pipeline.isAllowedSize(size);
  }

  static String _extensionFor(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('png')) {
      return 'png';
    }
    if (lower.contains('webp')) {
      return 'webp';
    }
    return 'jpg';
  }

  Future<void> _cancel(UploadTask? task) async {
    try {
      await task?.cancel();
    } on Object {
      // Best-effort cancel on timeout.
    }
  }

  void _log(String message, {required String path}) {
    if (!kDebugMode) {
      return;
    }
    final name = path.contains('/chat/') ? 'CHAT_UPLOAD' : 'PHOTO_UPLOAD';
    developer.log(message, name: name);
  }

  void _logError(
    String message, {
    required String code,
    String path = '',
  }) {
    if (!kDebugMode) {
      return;
    }
    final name = path.contains('/chat/')
        ? 'CHAT_UPLOAD_ERROR'
        : 'PHOTO_UPLOAD_ERROR';
    developer.log(
      'Code: $code Message: $message',
      name: name,
    );
  }
}
