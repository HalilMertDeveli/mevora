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
enum IdentityVerificationProvider {
  sumsub,
  didit;

  String get wireName => switch (this) {
    IdentityVerificationProvider.sumsub => 'sumsub',
    IdentityVerificationProvider.didit => 'didit',
  };
}

enum IdentityVerificationStatus {
  notStarted,
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
      this == IdentityVerificationStatus.inProgress ||
      this == IdentityVerificationStatus.inReview;

  /// The user may start a new verification session from this state.
  bool get canStart => !grantsVerifiedBadge && !isInFlight;
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
    'in_progress' => IdentityVerificationStatus.inProgress,
    'in_review' => IdentityVerificationStatus.inReview,
    'verified' => IdentityVerificationStatus.verified,
    'declined' => IdentityVerificationStatus.declined,
    'expired' => IdentityVerificationStatus.expired,
    'error' => IdentityVerificationStatus.error,
    _ => IdentityVerificationStatus.error,
  };
}

String identityVerificationStatusToFirestore(IdentityVerificationStatus status) {
  return switch (status) {
    IdentityVerificationStatus.notStarted => 'not_started',
    IdentityVerificationStatus.inProgress => 'in_progress',
    IdentityVerificationStatus.inReview => 'in_review',
    IdentityVerificationStatus.verified => 'verified',
    IdentityVerificationStatus.declined => 'declined',
    IdentityVerificationStatus.expired => 'expired',
    IdentityVerificationStatus.error => 'error',
  };
}

/// The minimum verification metadata MEVORA holds on the client.
///
/// Document images, selfies, liveness video and ID numbers are deliberately
/// absent and must stay absent: they live with the provider.
class IdentityVerification {
  const IdentityVerification({
    required this.status,
    this.provider,
    this.providerSessionId,
    this.updatedAt,
    this.verifiedAt,
  });

  final IdentityVerificationStatus status;
  final IdentityVerificationProvider? provider;
  final String? providerSessionId;
  final DateTime? updatedAt;
  final DateTime? verifiedAt;

  static const notStarted = IdentityVerification(
    status: IdentityVerificationStatus.notStarted,
  );

  IdentityVerification copyWith({
    IdentityVerificationStatus? status,
    IdentityVerificationProvider? provider,
    String? providerSessionId,
    DateTime? updatedAt,
    DateTime? verifiedAt,
  }) {
    return IdentityVerification(
      status: status ?? this.status,
      provider: provider ?? this.provider,
      providerSessionId: providerSessionId ?? this.providerSessionId,
      updatedAt: updatedAt ?? this.updatedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
