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
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';

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

  /// The member's private surname. Held beside the draft rather than on it:
  /// [UserProfile] is the public projection and never carries a surname.
  String lastName = '';
  OnboardingStep step = OnboardingStep.basicInfo;
  List<OnboardingPhotoDraft> photoDrafts = const [];
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;

  /// Whether the server requires this member to have a verified Face Anchor.
  /// Set by the page from what the server answered; false until then.
  bool faceAnchorRequired = false;

  String? _uid;
  var _disposed = false;
  StreamSubscription<UserProfile?>? _serverProfile;

  bool get canGoBack => step.previous != null;

  bool get hasFaceAnchor =>
      photoDrafts.any((draft) => draft.remote?.isFaceAnchor ?? false);

  /// Enough photos, but none verified as the member yet.
  bool get needsFaceAnchor => faceAnchorRequired && !hasFaceAnchor;

  bool get hasMinPhotos =>
      photoDrafts.where((draft) => draft.hasImage).length >=
      OnboardingConfig.minPhotos;

  bool get isUploadingPhotos => photoDrafts.any((draft) => draft.isUploading);

  bool get canContinuePhotos =>
      hasMinPhotos &&
      !isUploadingPhotos &&
      !needsFaceAnchor &&
      photoDrafts.every((draft) => !draft.hasImage || draft.remote != null);

  void setFaceAnchorRequired(bool value) {
    if (faceAnchorRequired == value) {
      return;
    }
    faceAnchorRequired = value;
    _notify();
  }

  /// [cityHint] is the city the member already chose at the location step
  /// ("Choose a city instead"). It fills a draft that has no city yet, so
  /// they are not asked for it a second time; a city already in the draft
  /// wins.
  Future<void> initialize(AuthUser user, {String? cityHint}) async {
    _uid = user.id;
    isLoading = true;
    errorMessage = null;
    _notify();
    final savedLastName = _loadLastName(user.id);
    final existing = await _repository.loadDraft(user.id);
    lastName = await savedLastName;
    final draft = (existing ??
            UserProfile(
              uid: user.id,
              displayName: user.displayName?.trim() ?? '',
            ))
        .copyWith(
          displayName: _prefillName(existing?.displayName, user.displayName),
          city: _prefillCity(existing?.city, cityHint),
        );
    profile = draft;
    // A draft started before the surname was collected resumes on the step
    // that asks for it, instead of failing at the very end.
    step = draft.onboardingStep == OnboardingStep.complete || lastName.isEmpty
        ? OnboardingStep.basicInfo
        : draft.onboardingStep;
    photoDrafts = _normalizedDrafts(_draftsFromProfile(draft));
    isLoading = false;
    _notify();
    _watchServerPhotos(user.id);
  }

  /// Follows the member's profile document for what only the server knows
  /// about each photo: whether moderation approved it and whether it was
  /// verified as the member. Uploads and moderation finish while the member
  /// is still on the photo step, so this is how the step finds out.
  void _watchServerPhotos(String uid) {
    unawaited(_serverProfile?.cancel());
    _serverProfile = _repository.watchDraft(uid).listen(
      (server) {
        if (server != null) {
          _applyServerPhotos(server.photos);
        }
      },
      onError: (Object _) {},
    );
  }

  /// Overlays server-owned fields onto the drafts, by photo id. The drafts
  /// stay the member's list: nothing is added or removed here, and a photo
  /// still uploading is left alone.
  void _applyServerPhotos(List<ProfilePhoto> serverPhotos) {
    if (_disposed || serverPhotos.isEmpty) {
      return;
    }
    final byId = {for (final photo in serverPhotos) photo.id: photo};
    var changed = false;
    final next = <OnboardingPhotoDraft>[];
    for (final draft in photoDrafts) {
      final remote = draft.remote;
      final server = byId[draft.id];
      if (remote == null || server == null) {
        next.add(draft);
        continue;
      }
      final published = server.isPublic;
      final merged = remote.copyWith(
        moderationStatus: server.moderationStatus,
        isFaceAnchorVerified: server.isFaceAnchorVerified,
        isPrimary: server.isFaceAnchor ? server.isPrimary : remote.isPrimary,
        // Once approved, the photo lives at its published location.
        storagePath: published && server.storagePath.isNotEmpty
            ? server.storagePath
            : null,
        downloadUrl: published ? server.downloadUrl : null,
        thumbUrl: server.thumbUrl,
        cardUrl: server.cardUrl,
      );
      if (merged.moderationStatus != remote.moderationStatus ||
          merged.isFaceAnchorVerified != remote.isFaceAnchorVerified ||
          merged.isPrimary != remote.isPrimary ||
          merged.storagePath != remote.storagePath ||
          merged.downloadUrl != remote.downloadUrl ||
          merged.thumbUrl != remote.thumbUrl ||
          merged.cardUrl != remote.cardUrl) {
        changed = true;
      }
      next.add(draft.copyWith(remote: merged));
    }
    if (!changed) {
      return;
    }
    photoDrafts = _normalizedDrafts(next);
    _syncPhotosToProfile();
    _notify();
  }

  /// With a verified Face Anchor among the drafts, the first one is the
  /// primary photo and must be an anchor: the one the server marks primary,
  /// otherwise the first anchor in the list.
  List<OnboardingPhotoDraft> _normalizedDrafts(List<OnboardingPhotoDraft> drafts) {
    bool isAnchor(OnboardingPhotoDraft draft) =>
        draft.remote?.isFaceAnchor ?? false;
    if (drafts.isEmpty || !drafts.any(isAnchor) || isAnchor(drafts.first)) {
      return drafts;
    }
    final primary =
        drafts
            .where((draft) => isAnchor(draft) && draft.remote!.isPrimary)
            .firstOrNull ??
        drafts.firstWhere(isAnchor);
    return [primary, ...drafts.where((draft) => draft.id != primary.id)];
  }

  /// The hint, when the draft has no city of its own. Null leaves the draft
  /// as it is.
  static String? _prefillCity(String? saved, String? hint) {
    if ((saved ?? '').trim().isNotEmpty) {
      return null;
    }
    final city = hint?.trim() ?? '';
    return city.isEmpty ? null : city;
  }

  void updateDraft(UserProfile Function(UserProfile current) transform) {
    final current = profile;
    if (current == null) {
      return;
    }
    profile = transform(current);
    _notify();
  }

  void updateLastName(String value) {
    lastName = value;
    _notify();
  }

  Future<String> _loadLastName(String uid) async {
    try {
      return await _repository.loadLastName(uid) ?? '';
    } on Object {
      return '';
    }
  }

  Future<Result<void>> continueStep() async {
    if (isSaving) {
      return const Err(ValidationFailure('Request already in progress'));
    }
    final uid = _uid;
    if (profile == null || uid == null) {
      return const Err(ValidationFailure('Profile is not ready yet'));
    }
    isSaving = true;
    errorMessage = null;
    _notify();
    try {
      if (step == OnboardingStep.photos) {
        if (!canContinuePhotos) {
          final reason = hasMinPhotos && needsFaceAnchor
              ? OnboardingMessages.faceAnchorRequired
              : PhotoUploadMessages.minRequired;
          _fail(reason);
          return Err(ValidationFailure(reason));
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
      final result = await _repository.saveStep(
        profile: current,
        step: step,
        lastName: lastName,
        requireFaceAnchor: faceAnchorRequired,
      );
      switch (result) {
        case Success(:final value):
          profile = value;
          final next = step.next;
          if (next != null) {
            step = next;
          }
          errorMessage = null;
          isSaving = false;
          _notify();
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
    if (isSaving) {
      return const Err(ValidationFailure('Request already in progress'));
    }
    final uid = _uid;
    if (profile == null || uid == null) {
      return const Err(ValidationFailure('Profile is not ready yet'));
    }
    isSaving = true;
    errorMessage = null;
    _notify();
    try {
      final upload = await _ensurePhotosUploaded(uid);
      if (upload.isError) {
        _fail(PhotoUploadMessages.failed);
        return upload;
      }
      final withPhotos = profile!.copyWith(photos: _photosFromDrafts());
      final result = await _repository.complete(
        withPhotos,
        lastName: lastName,
        requireFaceAnchor: faceAnchorRequired,
      );
      switch (result) {
        case Success(:final value):
          profile = value;
          step = OnboardingStep.complete;
          errorMessage = null;
          isSaving = false;
          _notify();
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
    _notify();
  }

  Future<Result<void>> pickPhoto({required bool fromCamera}) async {
    final uid = _uid;
    if (uid == null) {
      return const Err(ValidationFailure(PhotoUploadMessages.needSignIn));
    }
    if (photoDrafts.where((draft) => draft.hasImage).length >=
        OnboardingConfig.maxPhotos) {
      return Err(ValidationFailure(OnboardingMessages.photosTooMany));
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
        _notify();
        return _uploadDraft(uid, id);
      case Err(:final failure):
        errorMessage = failure.message;
        _notify();
        return Err(failure);
    }
  }

  /// Adds every photo picked in one gallery interaction, up to the remaining
  /// slots. Each one goes through the same draft + upload path as a single
  /// pick, so moderation and the pending-storage route are unchanged.
  Future<Result<void>> pickGalleryPhotos() async {
    final uid = _uid;
    if (uid == null) {
      return const Err(ValidationFailure(PhotoUploadMessages.needSignIn));
    }
    final remaining =
        OnboardingConfig.maxPhotos -
        photoDrafts.where((draft) => draft.hasImage).length;
    if (remaining <= 0) {
      return Err(ValidationFailure(OnboardingMessages.photosTooMany));
    }

    final picked = await _photoPicker.pickMultipleFromGallery(
      limit: remaining,
    );
    switch (picked) {
      case Success(:final value):
        if (value.isEmpty) {
          return const Err(ValidationFailure(PhotoUploadMessages.noneSelected));
        }
        final ids = <String>[];
        final added = <OnboardingPhotoDraft>[];
        final base = DateTime.now().microsecondsSinceEpoch;
        for (var i = 0; i < value.length && i < remaining; i += 1) {
          // Unique even within the same microsecond: a batch pick would
          // otherwise collide and overwrite its own drafts.
          final id = '${base + i}';
          ids.add(id);
          added.add(
            OnboardingPhotoDraft(
              id: id,
              localBytes: value[i].bytes,
              contentType: value[i].contentType,
            ),
          );
        }
        photoDrafts = [...photoDrafts, ...added];
        // A new pick supersedes an earlier cancelled one.
        errorMessage = null;
        _notify();

        // Upload sequentially; one failure must not discard the others.
        Failure? firstFailure;
        for (final id in ids) {
          final result = await _uploadDraft(uid, id);
          if (result.isError) {
            firstFailure ??= result.failureOrNull;
          }
        }
        if (firstFailure != null) {
          return Err(firstFailure);
        }
        return const Success(null);
      case Err(:final failure):
        errorMessage = failure.message;
        _notify();
        return Err(failure);
    }
  }

  /// Removes a photo, unless it is the member's only verified Face Anchor:
  /// that one stays until another photo has been verified.
  void removePhoto(String id) {
    final target = photoDrafts.where((draft) => draft.id == id).firstOrNull;
    final isAnchor = target?.remote?.isFaceAnchor ?? false;
    final otherAnchors = photoDrafts.any(
      (draft) => draft.id != id && (draft.remote?.isFaceAnchor ?? false),
    );
    if (isAnchor && !otherAnchors) {
      errorMessage = PhotoPolicy.lastFaceAnchor;
      _notify();
      return;
    }
    photoDrafts = _normalizedDrafts([
      for (final draft in photoDrafts)
        if (draft.id != id) draft,
    ]);
    errorMessage = null;
    _syncPhotosToProfile();
    _notify();
  }

  /// Moves a photo. Once a photo is verified, the first position is the
  /// primary photo, so only a verified photo can be moved into it.
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
    if (hasFaceAnchor && !(drafts.first.remote?.isFaceAnchor ?? false)) {
      errorMessage = PhotoPolicy.primaryRequiresFaceAnchor;
      _notify();
      return;
    }
    photoDrafts = drafts;
    errorMessage = null;
    _syncPhotosToProfile();
    _notify();
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
    _notify();
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
          _notify();
        },
      );
      switch (upload) {
        case Success(:final value):
          final latest = photoDrafts.indexWhere((item) => item.id == id);
          final extension = draft.contentType.contains('png')
              ? 'png'
              : draft.contentType.contains('webp')
              ? 'webp'
              : 'jpg';
          final remote = ProfilePhoto(
            id: draft.id,
            storagePath: StoragePaths.profilePending(
              ownerUid: uid,
              imageId: draft.id,
              extension: extension,
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
          _notify();
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
    _notify();
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
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_serverProfile?.cancel());
    super.dispose();
  }
}
