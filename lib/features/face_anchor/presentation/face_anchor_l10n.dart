import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/domain/face_anchor_messages.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Face Anchor outcomes in the member's language.
///
/// The server sends closed reason codes, never provider wording, so nothing
/// here can leak a score or a technical detail: an unknown code falls back to
/// the generic sentence.
abstract final class FaceAnchorL10n {
  /// Why a finished attempt did not verify the photo.
  static String reason(AppLocalizations l10n, FaceAnchorReason? reason) {
    return switch (reason) {
      FaceAnchorReason.livenessFailed => l10n.faceAnchorLivenessFailed,
      FaceAnchorReason.faceMismatch => l10n.faceAnchorMismatch,
      FaceAnchorReason.photoFaceUnclear => l10n.faceAnchorPhotoUnclear,
      FaceAnchorReason.selfieInvalid => l10n.faceAnchorSelfieInvalid,
      FaceAnchorReason.technicalError || null => l10n.faceAnchorTechnicalError,
    };
  }

  /// Why a verification could not be attempted or completed.
  static String error(AppLocalizations l10n, String? key) {
    return switch (key) {
      FaceAnchorMessages.unavailable => l10n.faceAnchorErrorUnavailable,
      FaceAnchorMessages.consentRequired => l10n.faceAnchorErrorConsent,
      FaceAnchorMessages.photoNotApproved =>
        l10n.faceAnchorErrorPhotoNotApproved,
      FaceAnchorMessages.alreadyVerified => l10n.faceAnchorVerified,
      FaceAnchorMessages.inProgress => l10n.faceAnchorErrorInProgress,
      FaceAnchorMessages.cooldown ||
      FaceAnchorMessages.tooManyRequests => l10n.faceAnchorErrorCooldown,
      FaceAnchorMessages.attemptLimit => l10n.faceAnchorErrorAttemptLimit,
      FaceAnchorMessages.cameraDenied ||
      FaceAnchorMessages.captureFailed => l10n.faceAnchorErrorCamera,
      FaceAnchorMessages.uploadFailed ||
      FaceAnchorMessages.network => l10n.faceAnchorErrorUpload,
      _ => l10n.faceAnchorErrorGeneric,
    };
  }

  /// The one-line status under a photo in the member's own list, or null when
  /// there is nothing to say about verification for it.
  static String? photoStatus(
    AppLocalizations l10n,
    FaceAnchorPhotoStatus status,
  ) {
    return switch (status) {
      FaceAnchorPhotoStatus.verified => l10n.faceAnchorVerified,
      FaceAnchorPhotoStatus.verifying => l10n.faceAnchorPending,
      FaceAnchorPhotoStatus.inReview => l10n.faceAnchorPhotoInReview,
      FaceAnchorPhotoStatus.notVerified => l10n.faceAnchorNotVerified,
      FaceAnchorPhotoStatus.canVerify || FaceAnchorPhotoStatus.none => null,
    };
  }
}
