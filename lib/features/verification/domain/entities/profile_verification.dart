/// Trusted verification state stored at `users/{uid}/verification/sumsub`.
///
/// Age gating (18+) remains on onboarding birthDate (`profileSafety.ts`).
/// Sumsub level may add document-based age checks later; do not surface that
/// in UI until the level is configured and webhook-approved in production.
enum ProfileVerificationStatus {
  notStarted,
  started,
  pending,
  approved,
  rejected,
  retryRequired;

  bool get isApproved => this == ProfileVerificationStatus.approved;

  bool get canStart =>
      this == ProfileVerificationStatus.notStarted ||
      this == ProfileVerificationStatus.started ||
      this == ProfileVerificationStatus.rejected ||
      this == ProfileVerificationStatus.retryRequired;

  bool get isInProgress =>
      this == ProfileVerificationStatus.started ||
      this == ProfileVerificationStatus.pending;
}

class ProfileVerification {
  const ProfileVerification({
    required this.status,
    this.verificationLevel,
    this.sumsubApplicantId,
    this.verificationUpdatedAt,
    this.verifiedAt,
    this.verificationAttemptCount = 0,
    this.lastVerificationAttemptAt,
  });

  final ProfileVerificationStatus status;
  final String? verificationLevel;
  final String? sumsubApplicantId;
  final DateTime? verificationUpdatedAt;
  final DateTime? verifiedAt;
  final int verificationAttemptCount;
  final DateTime? lastVerificationAttemptAt;

  static const notStarted = ProfileVerification(
    status: ProfileVerificationStatus.notStarted,
  );

  ProfileVerification copyWith({
    ProfileVerificationStatus? status,
    String? verificationLevel,
    String? sumsubApplicantId,
    DateTime? verificationUpdatedAt,
    DateTime? verifiedAt,
    int? verificationAttemptCount,
    DateTime? lastVerificationAttemptAt,
  }) {
    return ProfileVerification(
      status: status ?? this.status,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      sumsubApplicantId: sumsubApplicantId ?? this.sumsubApplicantId,
      verificationUpdatedAt:
          verificationUpdatedAt ?? this.verificationUpdatedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      verificationAttemptCount:
          verificationAttemptCount ?? this.verificationAttemptCount,
      lastVerificationAttemptAt:
          lastVerificationAttemptAt ?? this.lastVerificationAttemptAt,
    );
  }
}

ProfileVerificationStatus profileVerificationStatusFromFirestore(Object? raw) {
  return switch (raw) {
    'started' => ProfileVerificationStatus.started,
    'pending' => ProfileVerificationStatus.pending,
    'approved' => ProfileVerificationStatus.approved,
    'rejected' => ProfileVerificationStatus.rejected,
    'retry_required' => ProfileVerificationStatus.retryRequired,
    _ => ProfileVerificationStatus.notStarted,
  };
}

String profileVerificationStatusToFirestore(ProfileVerificationStatus status) {
  return switch (status) {
    ProfileVerificationStatus.notStarted => 'not_started',
    ProfileVerificationStatus.started => 'started',
    ProfileVerificationStatus.pending => 'pending',
    ProfileVerificationStatus.approved => 'approved',
    ProfileVerificationStatus.rejected => 'rejected',
    ProfileVerificationStatus.retryRequired => 'retry_required',
  };
}
