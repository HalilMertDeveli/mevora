import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/features/support/domain/models/support_message.dart';
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
            for (final doc in snap.docs) _ticketFromMap(doc.id, doc.data()),
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
    return _ticketFromMap(snap.id, data);
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

  /// The thread under `supportTickets/{ticketId}/messages`.
  ///
  /// The visibility filter is required, not decorative: the rules only let
  /// the owner read messages whose `visibility` is `user`, and a query
  /// that could match anything else is rejected as a whole. There is no
  /// composite index for this collection, so the order is applied here.
  /// Staff notes live in a separate collection the app never queries.
  Stream<List<SupportMessage>> watchMessages(String ticketId) {
    return _tickets
        .doc(ticketId)
        .collection(supportMessagesCollection)
        .where('visibility', isEqualTo: userVisibility)
        .snapshots()
        .map(
          (snap) => messagesFromDocs([
            for (final doc in snap.docs) (id: doc.id, data: doc.data()),
          ]),
        );
  }

  static const String supportMessagesCollection = 'messages';
  static const String userVisibility = 'user';

  /// Maps and orders thread documents. Anything not marked for the member
  /// is dropped even if it arrives, so a staff note can never render.
  @visibleForTesting
  static List<SupportMessage> messagesFromDocs(
    List<({String id, Map<String, dynamic> data})> docs,
  ) {
    final messages = <SupportMessage>[
      for (final doc in docs)
        if (doc.data['visibility'] == userVisibility)
          SupportMessage(
            id: doc.id,
            text: (doc.data['text'] as String?)?.trim() ?? '',
            authorLabel: (doc.data['authorLabel'] as String?)?.trim() ?? '',
            createdAt: firestoreDate(doc.data['createdAt']),
          ),
    ]..removeWhere((message) => message.text.isEmpty);
    messages.sort(SupportMessage.compareByTime);
    return messages;
  }

  @visibleForTesting
  static SupportTicket ticketFromMap(String id, Map<String, dynamic> data) =>
      _ticketFromMap(id, data);

  static SupportTicket _ticketFromMap(String id, Map<String, dynamic> data) {
    final attachments = data['attachments'];
    return SupportTicket(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      category:
          (data['category'] as String?) ?? SupportTicketCategory.other.name,
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
      supportReplyCount: firestoreInt(data['supportReplyCount'], 0),
      hasUnreadSupportReply: firestoreFlag(data['hasUnreadSupportReply']),
      lastSupportReplyAt: firestoreDate(data['lastSupportReplyAt']),
    );
  }
}
