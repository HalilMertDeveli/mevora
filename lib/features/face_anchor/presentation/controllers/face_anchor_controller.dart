import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/domain/face_anchor_messages.dart';
import 'package:mevora/features/face_anchor/domain/repositories/face_anchor_repository.dart';
import 'package:mevora/features/face_anchor/domain/services/live_selfie_capture.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// What the verification screen is doing on this device right now.
enum FaceAnchorPhase { idle, opening, capturing, uploading, verifying }

/// How one run of [FaceAnchorController.verify] ended.
enum FaceAnchorRunOutcome {
  verified,

  /// The server answered, and the answer was not "verified". See
  /// [FaceAnchorController.state] for the reason.
  notVerified,

  /// The member closed the camera. Nothing was sent.
  cancelled,

  /// It could not be attempted or completed. See
  /// [FaceAnchorController.errorKey].
  failed,

  /// The request was sent and the answer has not arrived. The server state
  /// stream will deliver it.
  pending,
}

/// Drives Face Anchor verification for the signed-in member.
///
/// Holds two things: what the server says ([state], [requirements]) and what
/// this device is in the middle of ([phase]). The first is never inferred from
/// the second — after a restart there is no phase at all, and the screen is
/// rebuilt from the server state alone.
class FaceAnchorController extends ChangeNotifier {
  FaceAnchorController({
    required FaceAnchorRepository repository,
    required LiveSelfieCapture capture,
    this.recoveryDelay = const Duration(seconds: 95),
  }) : _repository = repository,
       _capture = capture;

  final FaceAnchorRepository _repository;
  final LiveSelfieCapture _capture;

  /// How long a `processing` state is left alone before the server is asked
  /// about it again. Just past the server's own "this invocation is dead"
  /// threshold, so the question settles an abandoned attempt.
  final Duration recoveryDelay;

  FaceAnchorState state = FaceAnchorState.none;
  FaceAnchorRequirements requirements = FaceAnchorRequirements.unknown;
  FaceAnchorPhase phase = FaceAnchorPhase.idle;

  /// A [FaceAnchorMessages] identifier for the last run that could not be
  /// completed, or null.
  String? errorKey;

  String? _uid;
  String? _busyPhotoId;
  StreamSubscription<FaceAnchorState>? _subscription;
  Timer? _recovery;
  var _disposed = false;

  bool get isBusy => phase != FaceAnchorPhase.idle;

  /// The photo a verification is being driven for on this device.
  String? get busyPhotoId => _busyPhotoId;

  /// Starts following the member's server state. Safe to call again with the
  /// same uid; a different uid replaces the previous binding.
  void bind(String uid) {
    if (_uid == uid) {
      return;
    }
    _uid = uid;
    state = FaceAnchorState.none;
    unawaited(_subscription?.cancel());
    _subscription = _repository
        .watchState(uid)
        .listen(
          _onState,
          // A dropped listener leaves the last known state on screen; the next
          // snapshot or run corrects it.
          onError: (Object _) {},
        );
    unawaited(refreshRequirements());
  }

  Future<void> refreshRequirements() async {
    final loaded = await _repository.loadRequirements();
    if (_disposed) {
      return;
    }
    requirements = loaded;
    notifyListeners();
  }

  FaceAnchorPhotoStatus statusFor(ProfilePhoto photo) {
    return FaceAnchorPhotoStatus.resolve(
      photo: photo,
      state: state,
      available: requirements.available,
      busyPhotoId: _busyPhotoId,
    );
  }

  /// Runs one verification of [photoId]: open an attempt, capture a selfie,
  /// send it, ask for the verdict.
  ///
  /// [consentGiven] must be the member's explicit agreement on the screen
  /// that explains the check; without it nothing is opened and no camera is
  /// shown.
  Future<FaceAnchorRunOutcome> verify({
    required String photoId,
    required bool consentGiven,
  }) async {
    if (isBusy) {
      return FaceAnchorRunOutcome.pending;
    }
    if (!consentGiven) {
      return _fail(FaceAnchorMessages.consentRequired);
    }
    errorKey = null;
    _busyPhotoId = photoId;
    _setPhase(FaceAnchorPhase.opening);

    final attempt = await _repository.startAttempt(
      photoId: photoId,
      consentVersion: requirements.consentVersion,
    );
    if (_disposed) {
      return FaceAnchorRunOutcome.failed;
    }
    final opened = attempt.valueOrNull;
    if (opened == null) {
      return _fail(attempt.failureOrNull?.message);
    }

    _setPhase(FaceAnchorPhase.capturing);
    final captured = await _capture.capture();
    if (_disposed) {
      return FaceAnchorRunOutcome.failed;
    }
    if (captured.isError) {
      return _fail(captured.failureOrNull?.message);
    }
    final selfie = captured.valueOrNull;
    if (selfie == null) {
      // Camera closed. The opened attempt simply expires; it cost nothing.
      _finish();
      return FaceAnchorRunOutcome.cancelled;
    }

    _setPhase(FaceAnchorPhase.uploading);
    final upload = await _repository.uploadSelfie(
      attempt: opened,
      bytes: selfie.bytes,
      contentType: selfie.contentType,
    );
    if (_disposed) {
      return FaceAnchorRunOutcome.failed;
    }
    if (upload.isError) {
      return _fail(upload.failureOrNull?.message);
    }

    _setPhase(FaceAnchorPhase.verifying);
    final submitted = await _repository.submitAttempt(opened.attemptId);
    if (_disposed) {
      return FaceAnchorRunOutcome.failed;
    }
    final result = submitted.valueOrNull;
    if (result == null) {
      return _fail(submitted.failureOrNull?.message);
    }
    // The callable's answer and the document stream say the same thing; taking
    // the answer here just spares the screen a frame of stale state.
    state = result;
    _finish();
    return switch (result.status) {
      FaceAnchorStatus.verified => FaceAnchorRunOutcome.verified,
      FaceAnchorStatus.processing => FaceAnchorRunOutcome.pending,
      _ => FaceAnchorRunOutcome.notVerified,
    };
  }

  void clearError() {
    if (errorKey == null) {
      return;
    }
    errorKey = null;
    notifyListeners();
  }

  void _onState(FaceAnchorState next) {
    if (_disposed) {
      return;
    }
    state = next;
    _scheduleRecovery();
    notifyListeners();
  }

  /// A `processing` state with nothing running here means the app was closed
  /// — or the answer was lost — mid-verification. The stream delivers the
  /// result if the server is still working; if its invocation died, asking
  /// once more is what closes the attempt. A repeat never re-runs anything.
  void _scheduleRecovery() {
    _recovery?.cancel();
    _recovery = null;
    final attemptId = state.attemptId;
    if (!state.isProcessing || attemptId == null || isBusy) {
      return;
    }
    _recovery = Timer(recoveryDelay, () {
      if (_disposed ||
          isBusy ||
          !state.isProcessing ||
          state.attemptId != attemptId) {
        return;
      }
      unawaited(_repository.submitAttempt(attemptId));
    });
  }

  FaceAnchorRunOutcome _fail(String? key) {
    errorKey = key ?? FaceAnchorMessages.generic;
    _finish();
    return FaceAnchorRunOutcome.failed;
  }

  void _finish() {
    _busyPhotoId = null;
    phase = FaceAnchorPhase.idle;
    _scheduleRecovery();
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setPhase(FaceAnchorPhase next) {
    phase = next;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recovery?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
