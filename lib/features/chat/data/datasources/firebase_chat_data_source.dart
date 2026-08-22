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

  String? get currentUid => _uidSource.currentUid;

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
    final cursor = await _messages(matchId).doc(before.id).get();
    Query<Map<String, dynamic>> query = _messages(matchId)
        .orderBy('createdAt', descending: true);
    if (cursor.exists) {
      query = query.startAfterDocument(cursor);
    } else {
      query = query.startAfter([Timestamp.fromDate(before.createdAt)]);
    }
    final snap = await query.limit(limit + 1).get();
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
  }) {
    return sendMediaMessage(
      matchId: matchId,
      receiverId: receiverId,
      type: MessageType.text,
      text: text,
    );
  }

  @override
  Future<ChatMessage> sendImage({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    throw UnsupportedError('Use ChatRepositoryImpl for image uploads');
  }

  @override
  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    throw UnsupportedError('Use ChatRepositoryImpl for voice uploads');
  }

  Future<ChatMessage> sendMediaMessage({
    required String matchId,
    required String receiverId,
    required MessageType type,
    String text = '',
    String? imageStoragePath,
    String? voiceStoragePath,
    String? mediaUrl,
    int? durationMs,
    String? messageId,
  }) async {
    final senderId = _uidSource.currentUid;
    if (senderId == null) {
      throw StateError('unauthenticated');
    }
    final ref = messageId == null
        ? _messages(matchId).doc()
        : _messages(matchId).doc(messageId);
    final payload = <String, dynamic>{
      'id': ref.id,
      'senderId': senderId,
      'receiverId': receiverId,
      'type': type.firestoreValue,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'readAt': null,
      'deleted': false,
      'status': MessageStatus.sent.firestoreValue,
      if (imageStoragePath != null) 'imageStoragePath': imageStoragePath,
      if (voiceStoragePath != null) 'voiceStoragePath': voiceStoragePath,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (durationMs != null) 'durationMs': durationMs,
    };
    await ref.set(payload);
    final preview = switch (type) {
      MessageType.image => '📷',
      MessageType.voice => '🎤',
      _ => text,
    };
    await _firestore.collection(FirestorePaths.matches).doc(matchId).set({
      'lastMessage': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ChatMessage(
      id: ref.id,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      type: type,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      imageStoragePath: imageStoragePath,
      voiceStoragePath: voiceStoragePath,
      mediaUrl: mediaUrl,
      durationMs: durationMs,
    );
  }

  String allocateMessageId(String matchId) => _messages(matchId).doc().id;

  @override
  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  }) async {
    final uid = _uidSource.currentUid;
    if (uid == null) {
      throw StateError('unauthenticated');
    }
    await _messages(matchId).doc(messageId).update({
      'deleted': true,
      'text': '',
      'mediaUrl': FieldValue.delete(),
    });
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
      deleted: data['deleted'] == true,
      imageStoragePath: data['imageStoragePath'] as String?,
      voiceStoragePath: data['voiceStoragePath'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
      durationMs: (data['durationMs'] as num?)?.toInt(),
    );
  }
}
