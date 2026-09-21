import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/storage/storage_provider.dart';
import 'package:mevora/features/support/data/datasources/firebase_support_data_source.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/features/support/domain/repositories/support_repository.dart';

class SupportRepositoryImpl implements SupportRepository {
  SupportRepositoryImpl({
    required FirebaseSupportDataSource dataSource,
    StorageProvider? storage,
  }) : _dataSource = dataSource,
       _storage = storage;

  final FirebaseSupportDataSource _dataSource;
  final StorageProvider? _storage;

  @override
  Stream<List<SupportTicket>> watchTickets(String userId) {
    return _dataSource.watchTickets(userId);
  }

  @override
  Future<SupportTicket?> getTicket({
    required String userId,
    required String ticketId,
  }) async {
    if (userId.isEmpty || ticketId.isEmpty) {
      return null;
    }
    final ticket = await _dataSource.getTicket(ticketId);
    if (ticket == null || ticket.userId != userId) {
      // Firestore rules already deny cross-owner reads; this keeps the
      // client from rendering a ticket it does not own if that ever changes.
      return null;
    }
    return ticket;
  }

  @override
  Future<SupportTicket> createTicket({
    required String userId,
    required SupportTicketDraft draft,
  }) async {
    final ticketId = _dataSource.allocateTicketId();
    final attachments = <String>[];
    final bytes = draft.attachmentBytes;
    final storage = _storage;
    if (bytes != null && bytes.isNotEmpty && storage != null) {
      final extension = _extensionFor(
        draft.attachmentContentType,
        draft.attachmentFileName,
      );
      final path = StoragePaths.supportAttachment(
        ownerUid: userId,
        ticketId: ticketId,
        fileName: 'attachment.$extension',
      );
      final uploaded = await storage.uploadBytes(
        path: path,
        bytes: bytes,
        contentType: draft.attachmentContentType ?? 'image/jpeg',
      );
      switch (uploaded) {
        case Err(:final failure):
          throw failure;
        case Success():
          attachments.add(path);
      }
    }
    await _dataSource.createTicket(
      ticketId: ticketId,
      userId: userId,
      category: draft.category,
      subject: draft.subject,
      message: draft.message,
      attachments: attachments,
    );
    final tickets = await _dataSource.watchTickets(userId).first;
    return tickets.firstWhere((ticket) => ticket.id == ticketId);
  }

  static String _extensionFor(String? contentType, String? fileName) {
    final lowerType = contentType?.toLowerCase() ?? '';
    if (lowerType.contains('png')) {
      return 'png';
    }
    if (lowerType.contains('webp')) {
      return 'webp';
    }
    final lowerName = fileName?.toLowerCase() ?? '';
    if (lowerName.endsWith('.png')) {
      return 'png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'webp';
    }
    return 'jpg';
  }
}
