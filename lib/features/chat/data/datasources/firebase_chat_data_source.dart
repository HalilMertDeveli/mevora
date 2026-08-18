import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';

/// Chat listener is scoped to the open conversation only.
class FirebaseChatDataSource implements ChatRepository {
  FirebaseChatDataSource({
    required AuthUidSource uidSource,
    FirebaseFirestore? firestore,
  }) : _uidSource = uidSource,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final AuthUidSource _uidSource;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messages(String matchId) {
    return _firestore.collection(FirestorePaths.matchMessages(matchId));
  }

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = ChatPolicy.pageSize}) {
    return _messages(matchId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final items = [
            for (final doc in snap.docs) _fromMap(doc.id, doc.data()),
          ];
          return items.reversed.toList(growable: false);
        });
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = ChatPolicy.pageSize,
  }) async {
    final snap = await _messages(matchId)
        .orderBy('createdAt', descending: true)
        .startAfter([Timestamp.fromDate(before.createdAt)])
        .limit(limit + 1)
        .get();
    final docs = snap.docs;
    final hasMore = docs.length > limit;
    final slice = hasMore ? docs.take(limit) : docs;
    final messages = [
      for (final doc in slice) _fromMap(doc.id, doc.data()),
    ].reversed.toList(growable: false);
    return ChatPage(messages: messages, hasMore: hasMore);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) async {
    final senderId = _uidSource.currentUid;
    if (senderId == null) {
      throw StateError('unauthenticated');
    }
    final ref = _messages(matchId).doc();
    final payload = {
      'id': ref.id,
      'senderId': senderId,
      'receiverId': receiverId,
      'type': MessageType.text.firestoreValue,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'readAt': null,
      'status': MessageStatus.sent.firestoreValue,
    };
    await ref.set(payload);
    await _firestore.collection(FirestorePaths.matches).doc(matchId).set({
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ChatMessage(
      id: ref.id,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      type: MessageType.text,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
    );
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) {
    return _markStatus(matchId, messages, MessageStatus.delivered);
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) {
    return _markStatus(matchId, messages, MessageStatus.read);
  }

  @override
  Future<void> setTyping({required String matchId, required bool isTyping}) {
    final uid = _uidSource.currentUid;
    if (uid == null) {
      return Future<void>.value();
    }
    return _firestore.doc(FirestorePaths.matchTyping(matchId)).set({
      uid: isTyping ? FieldValue.serverTimestamp() : FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return _firestore.doc(FirestorePaths.matchTyping(matchId)).snapshots().map((
      snap,
    ) {
      final data = snap.data() ?? const <String, dynamic>{};
      final result = <String, DateTime>{};
      data.forEach((key, value) {
        if (value is Timestamp) {
          result[key] = value.toDate();
        }
      });
      return result;
    });
  }

  Future<void> _markStatus(
    String matchId,
    List<ChatMessage> messages,
    MessageStatus status,
  ) async {
    final uid = _uidSource.currentUid;
    if (uid == null || messages.isEmpty) {
      return;
    }
    final batch = _firestore.batch();
    for (final message in messages) {
      if (status == MessageStatus.read && message.receiverId != uid) {
        continue;
      }
      final updates = <String, dynamic>{
        'status': status.firestoreValue,
      };
      if (status == MessageStatus.read) {
        updates['isRead'] = true;
        updates['readAt'] = FieldValue.serverTimestamp();
      }
      batch.update(_messages(matchId).doc(message.id), updates);
    }
    await batch.commit();
  }

  ChatMessage _fromMap(String id, Map<String, dynamic> data) {
    return ChatMessage(
      id: (data['id'] as String?) ?? id,
      senderId: (data['senderId'] as String?) ?? '',
      receiverId: (data['receiverId'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      type: MessageTypeX.fromFirestore(data['type'] as String?),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      status: MessageStatusX.fromFirestore(data['status'] as String?),
      isRead: data['isRead'] == true,
      readAt: data['readAt'] is Timestamp
          ? (data['readAt'] as Timestamp).toDate()
          : null,
      imageStoragePath: data['imageStoragePath'] as String?,
    );
  }
}
