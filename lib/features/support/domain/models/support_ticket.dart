enum SupportTicketStatus {
  open,
  inProgress,
  resolved,
  closed;

  String get firestoreValue => switch (this) {
    SupportTicketStatus.open => 'open',
    SupportTicketStatus.inProgress => 'in_progress',
    SupportTicketStatus.resolved => 'resolved',
    SupportTicketStatus.closed => 'closed',
  };

  static SupportTicketStatus fromFirestore(String? value) {
    return switch (value) {
      'in_progress' => SupportTicketStatus.inProgress,
      'resolved' => SupportTicketStatus.resolved,
      'closed' => SupportTicketStatus.closed,
      _ => SupportTicketStatus.open,
    };
  }
}

enum SupportTicketCategory {
  account,
  matches,
  messaging,
  photos,
  safety,
  technical,
  other;

  String get firestoreValue => name;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.userId,
    required this.category,
    required this.subject,
    required this.message,
    required this.attachments,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.supportReplyCount = 0,
    this.hasUnreadSupportReply = false,
    this.lastSupportReplyAt,
  });

  final String id;
  final String userId;
  final String category;
  final String subject;
  final String message;
  final List<String> attachments;
  final SupportTicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Server-owned reply bookkeeping written by the admin console. Missing on
  /// requests nobody has answered yet.
  final int supportReplyCount;
  final bool hasUnreadSupportReply;
  final DateTime? lastSupportReplyAt;

  /// Mevora support has answered at least once.
  bool get hasSupportReply =>
      supportReplyCount > 0 ||
      hasUnreadSupportReply ||
      lastSupportReplyAt != null;

  SupportTicket copyWith({SupportTicketStatus? status, DateTime? updatedAt}) {
    return SupportTicket(
      id: id,
      userId: userId,
      category: category,
      subject: subject,
      message: message,
      attachments: attachments,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      supportReplyCount: supportReplyCount,
      hasUnreadSupportReply: hasUnreadSupportReply,
      lastSupportReplyAt: lastSupportReplyAt,
    );
  }
}
