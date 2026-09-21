import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';

class FirebaseSupportDataSource {
  FirebaseSupportDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _firestore.collection(FirestorePaths.supportTickets);

  Stream<List<SupportTicket>> watchTickets(String userId) {
    return _tickets
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs) _fromMap(doc.id, doc.data()),
          ],
        );
  }

  Future<SupportTicket?> getTicket(String ticketId) async {
    if (ticketId.isEmpty) {
      return null;
    }
    final snap = await _tickets.doc(ticketId).get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      return null;
    }
    return _fromMap(snap.id, data);
  }

  Future<void> createTicket({
    required String ticketId,
    required String userId,
    required SupportTicketCategory category,
    required String subject,
    required String message,
    List<String> attachments = const [],
  }) async {
    final now = FieldValue.serverTimestamp();
    await _tickets.doc(ticketId).set({
      'userId': userId,
      'category': category.firestoreValue,
      'subject': subject.trim(),
      'message': message.trim(),
      'attachments': attachments,
      'status': SupportTicketStatus.open.firestoreValue,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  String allocateTicketId() => _tickets.doc().id;

  SupportTicket _fromMap(String id, Map<String, dynamic> data) {
    final attachments = data['attachments'];
    return SupportTicket(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      category: (data['category'] as String?) ?? SupportTicketCategory.other.name,
      subject: (data['subject'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      attachments: attachments is List
          ? attachments.map((item) => item.toString()).toList(growable: false)
          : const [],
      status: SupportTicketStatus.fromFirestore(data['status'] as String?),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
