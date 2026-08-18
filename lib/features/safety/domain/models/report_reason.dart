enum ReportReason {
  spam,
  harassment,
  inappropriateContent,
  scam,
  fakeProfile,
  underage,
  other,
}

extension ReportReasonX on ReportReason {
  String get firestoreValue => switch (this) {
    ReportReason.spam => 'spam',
    ReportReason.harassment => 'harassment',
    ReportReason.inappropriateContent => 'inappropriate_content',
    ReportReason.scam => 'scam',
    ReportReason.fakeProfile => 'fake_profile',
    ReportReason.underage => 'underage',
    ReportReason.other => 'other',
  };

  String get label => switch (this) {
    ReportReason.spam => 'Spam',
    ReportReason.harassment => 'Harassment',
    ReportReason.inappropriateContent => 'Inappropriate Content',
    ReportReason.scam => 'Scam',
    ReportReason.fakeProfile => 'Fake Profile',
    ReportReason.underage => 'Underage',
    ReportReason.other => 'Other',
  };
}

class UserReport {
  const UserReport({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.reason,
    required this.createdAt,
    required this.status,
    this.matchId,
    this.messageId,
    this.description,
  });

  final String id;
  final String reporterId;
  final String reportedUserId;
  final ReportReason reason;
  final DateTime createdAt;
  final String status;
  final String? matchId;
  final String? messageId;
  final String? description;
}
