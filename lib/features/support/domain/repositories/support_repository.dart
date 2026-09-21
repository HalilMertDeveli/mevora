import 'package:mevora/features/support/domain/models/support_ticket.dart';

class SupportTicketDraft {
  const SupportTicketDraft({
    required this.category,
    required this.subject,
    required this.message,
    this.attachmentBytes,
    this.attachmentContentType,
    this.attachmentFileName,
  });

  final SupportTicketCategory category;
  final String subject;
  final String message;
  final List<int>? attachmentBytes;
  final String? attachmentContentType;
  final String? attachmentFileName;
}

abstract class SupportRepository {
  Stream<List<SupportTicket>> watchTickets(String userId);

  /// Resolves a single ticket for direct/deep-link navigation.
  ///
  /// Returns `null` when the ticket does not exist or is not owned by
  /// [userId]. Callers must render a not-found state rather than fabricate
  /// placeholder ticket data.
  Future<SupportTicket?> getTicket({
    required String userId,
    required String ticketId,
  });

  Future<SupportTicket> createTicket({
    required String userId,
    required SupportTicketDraft draft,
  });
}
