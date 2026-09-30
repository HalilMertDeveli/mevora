/// One entry in a support request's user-visible thread
/// (`supportTickets/{ticketId}/messages/{messageId}`).
///
/// Written only by Mevora support through the admin console. Staff-only
/// notes live in a different collection the app never reads.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.text,
    required this.authorLabel,
    this.createdAt,
  });

  /// The label the admin console writes on every staff reply.
  static const String defaultAuthorLabel = 'Mevora Support';

  final String id;
  final String text;

  /// Who answered, as the member may see it ("Mevora Support").
  final String authorLabel;

  /// Null while the server timestamp of a just-written reply is pending.
  final DateTime? createdAt;

  /// Oldest first; a reply whose time is still pending goes last.
  static int compareByTime(SupportMessage a, SupportMessage b) {
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null && bt == null) {
      return a.id.compareTo(b.id);
    }
    if (at == null) {
      return 1;
    }
    if (bt == null) {
      return -1;
    }
    final byTime = at.compareTo(bt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}
