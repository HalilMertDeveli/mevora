import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Where the member's current Face Anchor verification attempt stands, as the
/// server recorded it. The client never derives this from what it did locally.
enum FaceAnchorStatus {
  /// No attempt has been opened.
  none,
  awaitingSelfie,
  processing,
  verified,
  failed,
  expired,
  error;

  static FaceAnchorStatus fromWire(Object? value) {
    return switch (value) {
      'awaiting_selfie' => awaitingSelfie,
      'processing' => processing,
      'verified' => verified,
      'failed' => failed,
      'expired' => expired,
      'error' => error,
      // Anything unrecognised is "nothing in progress", never "verified".
      _ => none,
    };
  }
}

/// Why an attempt did not verify. Coarse on purpose: enough to tell the member
/// what to try next, and all the server stores.
enum FaceAnchorReason {
  livenessFailed,
  faceMismatch,
  photoFaceUnclear,
  selfieInvalid,
  technicalError;

  static FaceAnchorReason? fromWire(Object? value) {
    return switch (value) {
      'liveness_failed' => livenessFailed,
      'face_mismatch' => faceMismatch,
      'photo_face_unclear' => photoFaceUnclear,
      'selfie_invalid' => selfieInvalid,
      'technical_error' => technicalError,
      _ => null,
    };
  }
}

class FaceAnchorState {
  const FaceAnchorState({
    required this.status,
    this.reason,
    this.photoId,
    this.attemptId,
  });

  static const none = FaceAnchorState(status: FaceAnchorStatus.none);

  final FaceAnchorStatus status;
  final FaceAnchorReason? reason;

  /// The profile photo this attempt is about.
  final String? photoId;
  final String? attemptId;

  /// Reads `users/{uid}/faceAnchor/state` or a callable response. Neither
  /// carries a score, an image or anything from the verification provider.
  factory FaceAnchorState.fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return none;
    }
    return FaceAnchorState(
      status: FaceAnchorStatus.fromWire(data['status']),
      reason: FaceAnchorReason.fromWire(data['reason']),
      photoId: data['photoId'] as String?,
      attemptId: data['attemptId'] as String?,
    );
  }

  bool get isProcessing => status == FaceAnchorStatus.processing;

  bool get didNotVerify =>
      status == FaceAnchorStatus.failed || status == FaceAnchorStatus.error;
}

/// An attempt the server opened: where the selfie goes, and until when.
class FaceAnchorAttempt {
  const FaceAnchorAttempt({
    required this.attemptId,
    required this.uploadPath,
    required this.expiresAt,
  });

  final String attemptId;
  final String uploadPath;
  final DateTime expiresAt;
}

/// What the server says about Face Anchor for this member right now.
class FaceAnchorRequirements {
  const FaceAnchorRequirements({
    required this.required,
    required this.available,
    required this.consentVersion,
  });

  /// Before the server has answered, and when it cannot be reached: nothing is
  /// demanded locally and nothing is offered. The server still enforces its
  /// own rule when the profile is completed.
  static const unknown = FaceAnchorRequirements(
    required: false,
    available: false,
    consentVersion: 0,
  );

  /// This member cannot complete their profile without a verified photo.
  final bool required;

  /// Verification can run at the moment.
  final bool available;

  /// The consent wording in force; sent back when an attempt is opened.
  final int consentVersion;
}

/// How one photo should present itself in the member's own photo list.
enum FaceAnchorPhotoStatus {
  /// Nothing to show: verification is not on offer for this photo right now.
  none,

  /// Approved and unverified: "Verify this photo".
  canVerify,

  /// Still in moderation; verification comes after.
  inReview,

  /// A verification of this photo is running.
  verifying,
  verified,

  /// The last attempt on this photo did not verify.
  notVerified;

  /// [busyPhotoId] is the photo a verification is being driven for on this
  /// device right now, before the server state has caught up.
  static FaceAnchorPhotoStatus resolve({
    required ProfilePhoto photo,
    required FaceAnchorState state,
    required bool available,
    String? busyPhotoId,
  }) {
    if (photo.isFaceAnchor) {
      return verified;
    }
    if (busyPhotoId == photo.id ||
        (state.isProcessing && state.photoId == photo.id)) {
      return verifying;
    }
    switch (photo.moderationStatus) {
      case 'pending':
      case 'processing':
      case 'manual_review':
        return inReview;
      case 'approved':
        break;
      default:
        return none;
    }
    if (state.didNotVerify && state.photoId == photo.id) {
      return notVerified;
    }
    return available ? canVerify : none;
  }
}
