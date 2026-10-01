import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/profile_photo_remover.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/features/settings/domain/validators/profile_edit_validator.dart';

class ProfilePhotoManager {
  ProfilePhotoManager({
    required SettingsHubRepository settingsHub,
    required StorageRepository storage,
    required ProfilePhotoRemover photoRemover,
  }) : _settingsHub = settingsHub,
       _storage = storage,
       _photoRemover = photoRemover;

  final SettingsHubRepository _settingsHub;
  final StorageRepository _storage;
  final ProfilePhotoRemover _photoRemover;

  Future<Result<UserProfile>> addPhoto({
    required UserProfile profile,
    required String imageId,
    required List<int> bytes,
    required String contentType,
  }) async {
    if (!PhotoPolicy.canAdd(profile.photos.length)) {
      return const Err(ValidationFailure('photo_max_exceeded'));
    }
    final upload = await _storage.uploadProfileImage(
      ownerUid: profile.uid,
      imageId: imageId,
      bytes: bytes,
      contentType: contentType,
    );
    if (upload.isError) {
      return Err(upload.failureOrNull!);
    }
    final downloadUrl = upload.valueOrNull!;
    final order = profile.photos.isEmpty
        ? 0
        : profile.photos.map((p) => p.order).reduce((a, b) => a > b ? a : b) +
              1;
    final isPrimary = profile.photos.isEmpty;
    final storagePath = StoragePaths.profilePending(
      ownerUid: profile.uid,
      imageId: imageId,
      extension: contentType.contains('png')
          ? 'png'
          : contentType.contains('webp')
          ? 'webp'
          : 'jpg',
    );
    final nextPhoto = ProfilePhoto(
      id: imageId,
      storagePath: storagePath,
      downloadUrl: downloadUrl.toString(),
      moderationStatus: 'pending',
      order: order,
      isPrimary: isPrimary,
    );
    final nextProfile = profile.copyWith(
      photos: PhotoPolicy.normalize([...profile.photos, nextPhoto]),
    );
    final validation = ProfileEditValidator.validateProfile(nextProfile);
    if (validation != null) {
      await _storage.deleteProfileImage(ownerUid: profile.uid, imageId: imageId);
      return Err(ValidationFailure(validation));
    }
    try {
      await _settingsHub.saveProfile(nextProfile);
      return Success(nextProfile);
    } on Object catch (error) {
      await _storage.deleteProfileImage(ownerUid: profile.uid, imageId: imageId);
      return Err(ValidationFailure(error.toString()));
    }
  }

  Future<Result<UserProfile>> deletePhoto({
    required UserProfile profile,
    required String photoId,
  }) async {
    final blockReason = PhotoPolicy.deleteBlockReason(profile.photos, photoId);
    if (blockReason != null) {
      return Err(ValidationFailure(blockReason));
    }
    final remaining = profile.photos.where((p) => p.id != photoId).toList();
    final nextProfile = profile.copyWith(
      photos: PhotoPolicy.normalize(remaining),
    );
    // The server takes the photo off the profile and deletes what is stored
    // for it. Writing the shorter list from here would only do the first.
    final removal = await _photoRemover.remove(photoId);
    final failure = removal.failureOrNull;
    if (failure == null) {
      return Success(nextProfile);
    }
    if (failure is! NotFoundFailure) {
      return Err(failure);
    }
    // A backend from before the server-side delete: remove the photo the way
    // the app always did. Its published copy stays in storage.
    try {
      await _settingsHub.saveProfile(nextProfile);
    } on Object catch (error) {
      return Err(ValidationFailure(error.toString()));
    }
    await _storage.deleteProfileImage(ownerUid: profile.uid, imageId: photoId);
    return Success(nextProfile);
  }

  Future<Result<UserProfile>> reorderPhotos({
    required UserProfile profile,
    required int oldIndex,
    required int newIndex,
  }) async {
    final blockReason = PhotoPolicy.reorderBlockReason(
      profile.photos,
      oldIndex,
      newIndex,
    );
    if (blockReason != null) {
      return Err(ValidationFailure(blockReason));
    }
    final reordered = PhotoPolicy.reorder(profile.photos, oldIndex, newIndex);
    final nextProfile = profile.copyWith(photos: reordered);
    try {
      await _settingsHub.saveProfile(nextProfile);
    } on Object catch (error) {
      return Err(ValidationFailure(error.toString()));
    }
    return Success(nextProfile);
  }

  Future<Result<UserProfile>> setPrimaryPhoto({
    required UserProfile profile,
    required String photoId,
  }) async {
    // Only a photo verified as the member can be the primary one. The server
    // imposes the same rule; refusing here just says so before the write.
    final blockReason = PhotoPolicy.setPrimaryBlockReason(
      profile.photos,
      photoId,
    );
    if (blockReason != null) {
      return Err(ValidationFailure(blockReason));
    }
    final nextProfile = profile.copyWith(
      photos: PhotoPolicy.setPrimary(profile.photos, photoId),
    );
    try {
      await _settingsHub.saveProfile(nextProfile);
    } on Object catch (error) {
      return Err(ValidationFailure(error.toString()));
    }
    return Success(nextProfile);
  }
}
