/// Stable identifiers for Face Anchor failures that are not a verification
/// verdict: the attempt could not be opened, the selfie could not be taken or
/// sent, or the server refused the call.
///
/// Domain and data code return these; `FaceAnchorL10n` turns them into the
/// member's language. They are never shown as-is.
abstract final class FaceAnchorMessages {
  static const unavailable = 'face_anchor_unavailable';
  static const consentRequired = 'face_anchor_consent_required';
  static const photoNotApproved = 'face_anchor_photo_not_approved';
  static const photoNotFound = 'face_anchor_photo_not_found';
  static const alreadyVerified = 'face_anchor_already_verified';
  static const inProgress = 'face_anchor_in_progress';
  static const cooldown = 'face_anchor_cooldown';
  static const attemptLimit = 'face_anchor_attempt_limit';
  static const tooManyRequests = 'face_anchor_too_many_requests';
  static const captureFailed = 'face_anchor_capture_failed';
  static const cameraDenied = 'face_anchor_camera_denied';
  static const uploadFailed = 'face_anchor_upload_failed';
  static const attemptExpired = 'face_anchor_attempt_expired';
  static const network = 'face_anchor_network';
  static const accountNotAllowed = 'face_anchor_account_not_allowed';
  static const generic = 'face_anchor_generic';
}
