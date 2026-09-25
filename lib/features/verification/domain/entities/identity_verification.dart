/// Provider-neutral identity verification domain.
///
/// MEVORA's screens must not learn who verifies identity. Sumsub's review
/// answers and Didit's session statuses are provider dialects; both are
/// translated into this vocabulary at the data-source boundary and never
/// leak past it.
///
/// The authority for [IdentityVerificationStatus.verified] is the backend
/// verification document written by the provider webhook. An SDK completion
/// callback is a UI hint only — it must never construct a verified state.
/// See `docs/DIDIT_MIGRATION_PHASE1.md` (STEP 12).
library;

/// Retry pacing, mirrored from the backend gates so the UI can explain a wait
/// instead of firing a call the server was always going to refuse. The server
/// remains the enforcer; these values are advisory.
const Duration identityVerificationCooldown = Duration(minutes: 15);
const int identityVerificationMaxAttemptsPerDay = 5;

enum IdentityVerificationProvider {
  sumsub,
  didit;

  String get wireName => switch (this) {
    IdentityVerificationProvider.sumsub => 'sumsub',
    IdentityVerificationProvider.didit => 'didit',
  };

  static IdentityVerificationProvider? fromWire(Object? raw) {
    return switch (raw) {
      'sumsub' => IdentityVerificationProvider.sumsub,
      'didit' => IdentityVerificationProvider.didit,
      _ => null,
    };
  }
}

enum IdentityVerificationStatus {
  notStarted,
  pending,
  inProgress,
  inReview,
  verified,
  declined,
  expired,
  error;

  /// The only predicate that may show the verified badge.
  bool get grantsVerifiedBadge => this == IdentityVerificationStatus.verified;

  /// No further provider transition is expected without a new session.
  bool get isTerminal =>
      this == IdentityVerificationStatus.verified ||
      this == IdentityVerificationStatus.declined ||
      this == IdentityVerificationStatus.expired;

  /// A session is with the provider or a reviewer right now.
  bool get isInFlight =>
      this == IdentityVerificationStatus.pending ||
      this == IdentityVerificationStatus.inProgress ||
      this == IdentityVerificationStatus.inReview;

  /// The user may start a new verification session from this state.
  ///
  /// Whether they may start one *right now* also depends on the cooldown and
  /// the daily attempt budget — see [IdentityVerification.retryEligibility].
  bool get canStart => !grantsVerifiedBadge && !isInFlight;
}

/// Why a fresh session cannot be started yet, in terms the UI can explain
/// without naming the provider or leaking a technical reason.
enum IdentityVerificationRetryBlock {
  alreadyVerified,
  inFlight,
  cooldown,
  dailyLimit,
}

class IdentityVerificationRetryEligibility {
  const IdentityVerificationRetryEligibility({
    required this.allowed,
    this.blockedBy,
    this.retryAvailableAt,
  });

  final bool allowed;
  final IdentityVerificationRetryBlock? blockedBy;
  final DateTime? retryAvailableAt;

  static const allowedNow = IdentityVerificationRetryEligibility(allowed: true);
}

/// A sanitized reason for a decline or a review hold.
///
/// This is a short, stable code chosen by MEVORA — never the provider's raw
/// reject label, review comment, document field or error text. Anything the
/// provider says about *why* a document failed is identity data; it stays
/// with the provider.
enum IdentityVerificationReason {
  documentUnreadable,
  documentUnsupported,
  livenessFailed,
  faceMismatch,
  manualReview,
  providerError;

  String get wireName => switch (this) {
    IdentityVerificationReason.documentUnreadable => 'document_unreadable',
    IdentityVerificationReason.documentUnsupported => 'document_unsupported',
    IdentityVerificationReason.livenessFailed => 'liveness_failed',
    IdentityVerificationReason.faceMismatch => 'face_mismatch',
    IdentityVerificationReason.manualReview => 'manual_review',
    IdentityVerificationReason.providerError => 'provider_error',
  };

  static IdentityVerificationReason? fromWire(Object? raw) {
    return switch (raw) {
      'document_unreadable' => IdentityVerificationReason.documentUnreadable,
      'document_unsupported' => IdentityVerificationReason.documentUnsupported,
      'liveness_failed' => IdentityVerificationReason.livenessFailed,
      'face_mismatch' => IdentityVerificationReason.faceMismatch,
      'manual_review' => IdentityVerificationReason.manualReview,
      'provider_error' => IdentityVerificationReason.providerError,
      _ => null,
    };
  }
}

/// Reads the status off the backend verification document.
///
/// An absent field is the legitimate initial state. Anything present but
/// unrecognised degrades to [IdentityVerificationStatus.error] rather than to
/// a status that could be read as progress — a provider that adds a value
/// MEVORA has not reviewed must not move a user toward verified by accident.
IdentityVerificationStatus identityVerificationStatusFromFirestore(Object? raw) {
  if (raw == null || raw == '') {
    return IdentityVerificationStatus.notStarted;
  }
  return switch (raw) {
    'not_started' => IdentityVerificationStatus.notStarted,
    'pending' => IdentityVerificationStatus.pending,
    'in_progress' => IdentityVerificationStatus.inProgress,
    'in_review' => IdentityVerificationStatus.inReview,
    'verified' => IdentityVerificationStatus.verified,
    'declined' => IdentityVerificationStatus.declined,
    'expired' => IdentityVerificationStatus.expired,
    'error' => IdentityVerificationStatus.error,
    _ => IdentityVerificationStatus.error,
  };
}

String identityVerificationStatusToFirestore(
  IdentityVerificationStatus status,
) {
  return switch (status) {
    IdentityVerificationStatus.notStarted => 'not_started',
    IdentityVerificationStatus.pending => 'pending',
    IdentityVerificationStatus.inProgress => 'in_progress',
    IdentityVerificationStatus.inReview => 'in_review',
    IdentityVerificationStatus.verified => 'verified',
    IdentityVerificationStatus.declined => 'declined',
    IdentityVerificationStatus.expired => 'expired',
    IdentityVerificationStatus.error => 'error',
  };
}

/// The current schema of the verification document MEVORA writes.
///
/// Bumped only when the document's shape changes in a way a reader must know
/// about. A document with no version is the pre-neutral (Sumsub-shaped)
/// layout and is read through `legacy_verification_bridge.dart`.
const int identityVerificationSchemaVersion = 1;

/// The minimum verification metadata MEVORA holds.
///
/// Document images, selfies, liveness video, document numbers and raw
/// provider payloads are deliberately absent and must stay absent: they live
/// with the provider. This class is also the deletion boundary — everything
/// MEVORA must erase for a departing user is represented here and lives in
/// one document, `users/{uid}/verification/identity`.
class IdentityVerification {
  const IdentityVerification({
    required this.status,
    this.provider,
    this.providerSessionId,
    this.createdAt,
    this.updatedAt,
    this.verifiedAt,
    this.reason,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.schemaVersion,
  });

  final IdentityVerificationStatus status;
  final IdentityVerificationProvider? provider;

  /// The provider's session/applicant reference. Server-written, and the only
  /// handle MEVORA needs to ask the provider to erase the user's data.
  final String? providerSessionId;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? verifiedAt;

  /// Sanitized — never the provider's raw reject text.
  final IdentityVerificationReason? reason;

  final int attemptCount;
  final DateTime? lastAttemptAt;

  /// Null for a legacy (pre-neutral) document.
  final int? schemaVersion;

  static const notStarted = IdentityVerification(
    status: IdentityVerificationStatus.notStarted,
  );

  /// Whether a fresh session may be started, and if not, when.
  ///
  /// Advisory only: the backend applies the same gates and is the enforcer.
  /// This exists so the UI can say "try again shortly" instead of firing a
  /// call the server will refuse.
  IdentityVerificationRetryEligibility retryEligibility({DateTime? now}) {
    if (status.grantsVerifiedBadge) {
      return const IdentityVerificationRetryEligibility(
        allowed: false,
        blockedBy: IdentityVerificationRetryBlock.alreadyVerified,
      );
    }
    if (status.isInFlight) {
      return const IdentityVerificationRetryEligibility(
        allowed: false,
        blockedBy: IdentityVerificationRetryBlock.inFlight,
      );
    }
    final last = lastAttemptAt;
    if (last == null) {
      return IdentityVerificationRetryEligibility.allowedNow;
    }
    final at = now ?? DateTime.now();
    final available = last.add(identityVerificationCooldown);
    if (at.isBefore(available)) {
      return IdentityVerificationRetryEligibility(
        allowed: false,
        blockedBy: IdentityVerificationRetryBlock.cooldown,
        retryAvailableAt: available,
      );
    }
    final withinDay = at.difference(last) < const Duration(days: 1);
    if (withinDay && attemptCount >= identityVerificationMaxAttemptsPerDay) {
      return IdentityVerificationRetryEligibility(
        allowed: false,
        blockedBy: IdentityVerificationRetryBlock.dailyLimit,
        retryAvailableAt: last.add(const Duration(days: 1)),
      );
    }
    return IdentityVerificationRetryEligibility.allowedNow;
  }

  IdentityVerification copyWith({
    IdentityVerificationStatus? status,
    IdentityVerificationProvider? provider,
    String? providerSessionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? verifiedAt,
    IdentityVerificationReason? reason,
    int? attemptCount,
    DateTime? lastAttemptAt,
    int? schemaVersion,
  }) {
    return IdentityVerification(
      status: status ?? this.status,
      provider: provider ?? this.provider,
      providerSessionId: providerSessionId ?? this.providerSessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      reason: reason ?? this.reason,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }
}
