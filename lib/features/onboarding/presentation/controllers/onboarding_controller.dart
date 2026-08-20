import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

class OnboardingPhotoDraft {
  const OnboardingPhotoDraft({
    required this.id,
    this.remote,
    this.localBytes,
    this.contentType = 'image/jpeg',
    this.progress = 0,
    this.isUploading = false,
    this.error,
  });

  final String id;
  final ProfilePhoto? remote;
  final List<int>? localBytes;
  final String contentType;
  final double progress;
  final bool isUploading;
  final String? error;

  bool get hasImage => remote != null || localBytes != null;

  OnboardingPhotoDraft copyWith({
    ProfilePhoto? remote,
    List<int>? localBytes,
    String? contentType,
    double? progress,
    bool? isUploading,
    String? error,
    bool clearError = false,
  }) {
    return OnboardingPhotoDraft(
      id: id,
      remote: remote ?? this.remote,
      localBytes: localBytes ?? this.localBytes,
      contentType: contentType ?? this.contentType,
      progress: progress ?? this.progress,
      isUploading: isUploading ?? this.isUploading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required OnboardingRepository repository,
    required StorageRepository storage,
    required ProfilePhotoPicker photoPicker,
  }) : _repository = repository,
       _storage = storage,
       _photoPicker = photoPicker;

  final OnboardingRepository _repository;
  final StorageRepository _storage;
  final ProfilePhotoPicker _photoPicker;

  UserProfile? profile;
  OnboardingStep step = OnboardingStep.basicInfo;
  List<OnboardingPhotoDraft> photoDrafts = const [];
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;

  String? _uid;

  bool get canGoBack => step.previous != null;

  bool get hasMinPhotos =>
      photoDrafts.where((draft) => draft.hasImage).length >=
      OnboardingConfig.minPhotos;

  bool get isUploadingPhotos => photoDrafts.any((draft) => draft.isUploading);

  bool get canContinuePhotos =>
      hasMinPhotos &&
      !isUploadingPhotos &&
      photoDrafts.every((draft) => !draft.hasImage || draft.remote != null);

  Future<void> initialize(AuthUser user) async {
    _uid = user.id;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    final existing = await _repository.loadDraft(user.id);
    final draft = (existing ??
            UserProfile(
              uid: user.id,
              displayName: user.displayName?.trim() ?? '',
            ))
        .copyWith(
          displayName: _prefillName(existing?.displayName, user.displayName),
        );
    profile = draft;
    step = draft.onboardingStep == OnboardingStep.complete
        ? OnboardingStep.basicInfo
        : draft.onboardingStep;
    photoDrafts = _draftsFromProfile(draft);
    isLoading = false;
    notifyListeners();
  }

  void updateDraft(UserProfile Function(UserProfile current) transform) {
    final current = profile;
    if (current == null) {
      return;
    }
    profile = transform(current);
    notifyListeners();
  }

  Future<Result<void>> continueStep() async {
    final uid = _uid;
    if (profile == null || uid == null) {
      return const Err(ValidationFailure('Profile is not ready yet'));
    }
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (step == OnboardingStep.photos) {
        if (!canContinuePhotos) {
          _fail(PhotoUploadMessages.minRequired);
          return const Err(ValidationFailure(PhotoUploadMessages.minRequired));
        }
        final upload = await _ensurePhotosUploaded(uid);
        if (upload.isError) {
          _fail(PhotoUploadMessages.failed);
          return upload;
        }
      }
      final current = profile;
      if (current == null) {
        _fail(PhotoUploadMessages.failed);
        return const Err(ValidationFailure('Profile is not ready yet'));
      }
      final result = await _repository.saveStep(profile: current, step: step);
      switch (result) {
        case Success(:final value):
          profile = value;
          final next = step.next;
          if (next != null) {
            step = next;
          }
          errorMessage = null;
          isSaving = false;
          notifyListeners();
          return const Success(null);
        case Err(:final failure):
          _fail(failure.message);
          return Err(failure);
      }
    } on Object {
      _fail(PhotoUploadMessages.failed);
      return const Err(NetworkFailure(PhotoUploadMessages.failed));
    }
  }

  Future<Result<void>> complete() async {
    final uid = _uid;
    if (profile == null || uid == null) {
      return const Err(ValidationFailure('Profile is not ready yet'));
    }
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      final upload = await _ensurePhotosUploaded(uid);
      if (upload.isError) {
        _fail(PhotoUploadMessages.failed);
        return upload;
      }
      final withPhotos = profile!.copyWith(photos: _photosFromDrafts());
      final result = await _repository.complete(withPhotos);
      switch (result) {
        case Success(:final value):
          profile = value;
          step = OnboardingStep.complete;
          errorMessage = null;
          isSaving = false;
          notifyListeners();
          return const Success(null);
        case Err(:final failure):
          _fail(failure.message);
          return Err(failure);
      }
    } on Object {
      _fail(PhotoUploadMessages.failed);
      return const Err(NetworkFailure(PhotoUploadMessages.failed));
    }
  }

  void goBack() {
    final previous = step.previous;
    if (previous == null) {
      return;
    }
    step = previous;
    errorMessage = null;
    notifyListeners();
  }

  Future<Result<void>> pickPhoto({required bool fromCamera}) async {
    final uid = _uid;
    if (uid == null) {
      return const Err(ValidationFailure(PhotoUploadMessages.needSignIn));
    }
    if (photoDrafts.where((draft) => draft.hasImage).length >=
        OnboardingConfig.maxPhotos) {
      return Err(
        ValidationFailure(
          'You can add up to ${OnboardingConfig.maxPhotos} photos',
        ),
      );
    }
    final picked = fromCamera
        ? await _photoPicker.pickFromCamera()
        : await _photoPicker.pickFromGallery();
    switch (picked) {
      case Success(:final value):
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        photoDrafts = [
          ...photoDrafts,
          OnboardingPhotoDraft(
            id: id,
            localBytes: value.bytes,
            contentType: value.contentType,
          ),
        ];
        notifyListeners();
        return _uploadDraft(uid, id);
      case Err(:final failure):
        errorMessage = failure.message;
        notifyListeners();
        return Err(failure);
    }
  }

  void removePhoto(String id) {
    photoDrafts = [
      for (final draft in photoDrafts)
        if (draft.id != id) draft,
    ];
    _syncPhotosToProfile();
    notifyListeners();
  }

  void reorderPhotos(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) {
      return;
    }
    final drafts = [...photoDrafts];
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = drafts.removeAt(oldIndex);
    drafts.insert(newIndex, item);
    photoDrafts = drafts;
    _syncPhotosToProfile();
    notifyListeners();
  }

  Future<Result<void>> retryPhotoUpload(String id) async {
    final uid = _uid;
    if (uid == null) {
      return const Err(ValidationFailure('Profile is not ready yet'));
    }
    return _uploadDraft(uid, id);
  }

  Future<Result<void>> _ensurePhotosUploaded(String uid) async {
    for (final draft in photoDrafts) {
      if (draft.remote != null || draft.localBytes == null) {
        continue;
      }
      final result = await _uploadDraft(uid, draft.id);
      if (result.isError) {
        return result;
      }
    }
    _syncPhotosToProfile();
    return const Success(null);
  }

  Future<Result<void>> _uploadDraft(String uid, String id) async {
    final index = photoDrafts.indexWhere((draft) => draft.id == id);
    if (index < 0) {
      return const Err(ValidationFailure('Photo not found'));
    }
    final draft = photoDrafts[index];
    if (draft.isUploading) {
      return const Success(null);
    }
    final bytes = draft.localBytes;
    if (bytes == null) {
      return const Success(null);
    }
    photoDrafts = [
      for (var i = 0; i < photoDrafts.length; i++)
        if (i == index)
          draft.copyWith(isUploading: true, progress: 0.05, clearError: true)
        else
          photoDrafts[i],
    ];
    notifyListeners();
    try {
      final upload = await _storage.uploadProfileImage(
        ownerUid: uid,
        imageId: draft.id,
        bytes: bytes,
        contentType: draft.contentType,
        onProgress: (value) {
          final latest = photoDrafts.indexWhere((item) => item.id == id);
          if (latest < 0) {
            return;
          }
          photoDrafts = [
            for (var i = 0; i < photoDrafts.length; i++)
              if (i == latest)
                photoDrafts[i].copyWith(progress: value, isUploading: true)
              else
                photoDrafts[i],
          ];
          notifyListeners();
        },
      );
      switch (upload) {
        case Success(:final value):
          final latest = photoDrafts.indexWhere((item) => item.id == id);
          final remote = ProfilePhoto(
            id: draft.id,
            storagePath: StoragePaths.profilePhoto(
              ownerUid: uid,
              imageId: draft.id,
              extension: draft.contentType.contains('png')
                  ? 'png'
                  : draft.contentType.contains('webp')
                  ? 'webp'
                  : 'jpg',
            ),
            downloadUrl: value.toString(),
            moderationStatus: 'pending',
            order: latest < 0 ? index : latest,
            isPrimary: (latest < 0 ? index : latest) == 0,
          );
          photoDrafts = [
            for (var i = 0; i < photoDrafts.length; i++)
              if (photoDrafts[i].id == id)
                photoDrafts[i].copyWith(
                  remote: remote,
                  isUploading: false,
                  progress: 1,
                  clearError: true,
                )
              else
                photoDrafts[i],
          ];
          _syncPhotosToProfile();
          notifyListeners();
          return const Success(null);
        case Err(:final failure):
          _markUploadFailed(id, PhotoUploadMessages.failed);
          return Err(failure);
      }
    } on Object {
      _markUploadFailed(id, PhotoUploadMessages.failed);
      return const Err(NetworkFailure(PhotoUploadMessages.failed));
    }
  }

  void _markUploadFailed(String id, String message) {
    photoDrafts = [
      for (final draft in photoDrafts)
        if (draft.id == id)
          draft.copyWith(
            isUploading: false,
            progress: 0,
            error: message,
          )
        else
          draft,
    ];
    notifyListeners();
  }

  List<OnboardingPhotoDraft> _draftsFromProfile(UserProfile value) {
    if (value.photos.isEmpty) {
      return const [];
    }
    return [
      for (final photo in value.photos)
        OnboardingPhotoDraft(id: photo.id, remote: photo),
    ];
  }

  List<ProfilePhoto> _photosFromDrafts() {
    final photos = <ProfilePhoto>[];
    for (var i = 0; i < photoDrafts.length; i++) {
      final draft = photoDrafts[i];
      final remote = draft.remote;
      if (remote == null) {
        continue;
      }
      photos.add(
        remote.copyWith(order: i, isPrimary: i == 0),
      );
    }
    return photos;
  }

  void _syncPhotosToProfile() {
    final current = profile;
    if (current == null) {
      return;
    }
    profile = current.copyWith(photos: _photosFromDrafts());
  }

  String _prefillName(String? existing, String? authName) {
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final hint = authName?.trim();
    if (hint == null || hint.isEmpty) {
      return '';
    }
    return hint.split(RegExp(r'\s+')).first;
  }

  void _fail(String message) {
    isSaving = false;
    errorMessage = message;
    notifyListeners();
  }
}
