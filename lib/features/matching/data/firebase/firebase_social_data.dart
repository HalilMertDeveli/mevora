import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/core/storage/storage_provider.dart';
import 'package:mevora/features/chat/data/datasources/firebase_chat_data_source.dart';
import 'package:mevora/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_chat_service.dart';
import 'package:mevora/features/profile/data/datasources/firebase_storage_data_source.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

DateTime? _time(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

Match _matchFrom(DocumentSnapshot<Map<String, dynamic>> snap) {
  final data = snap.data() ?? const <String, dynamic>{};
  final userIds = (data['userIds'] as List<dynamic>? ?? const [])
      .map((item) => item.toString())
      .toList(growable: false);
  return Match(
    id: snap.id,
    userIds: userIds,
    createdAt: _time(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    isActive: data['isActive'] as bool? ?? false,
    lastMessage: data['lastMessage'] as String?,
    lastMessageAt: _time(data['lastMessageAt']),
    unmatchedBy: data['unmatchedBy'] as String?,
    unmatchedAt: _time(data['unmatchedAt']),
    endedReason: data['endedReason'] as String?,
    unreadCounts: _stringIntMap(data['unreadCounts']),
    isNewFor: _stringBoolMap(data['isNewFor']),
    participantNames: _stringStringMap(data['participantNames']),
    participantPhotos: _stringStringMap(data['participantPhotos']),
    participantVerified: _stringBoolMap(data['participantVerified']),
    source: matchSourceFrom(data['source'], matchType: data['matchType']),
    compatibilitySnapshots: CompatibilitySnapshot.mapFromSnapshotsField(
      data['compatibilitySnapshots'],
    ),
  );
}

Map<String, int> _stringIntMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0));
  }
  return const {};
}

Map<String, bool> _stringBoolMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item == true));
  }
  return const {};
}

Map<String, String> _stringStringMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item.toString()));
  }
  return const {};
}

/// Retained deleted-account threads are few; cap the read so a long history
/// cannot turn the match list into an unbounded query.
const int _archivedLimit = 20;

class FirebaseMatchRepository implements MatchRepository, LikeRepository, DiscoveryExclusionSource {
  FirebaseMatchRepository({
    required this.callable,
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable callable;
  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  MatchListItem _listItem(Match match, String uid) {
    return MatchListItem(
      match: match,
      otherUserId: match.otherUserId(uid),
      name: match.otherName(uid),
      photoUrl: match.otherPhoto(uid),
      isVerified: match.otherIsVerified(uid),
      compatibility: match.compatibilityFor(uid),
    );
  }

  /// Retained conversations whose counterpart deleted their account.
  ///
  /// Reuses the (userIds CONTAINS, isActive, lastMessageAt) index the active
  /// query already needs — only the equality value differs — and stays bounded,
  /// so no new index and no unbounded read. Unmatched and blocked threads come
  /// back from the same query and are dropped by the classifier, never shown.
  @override
  Stream<List<MatchListItem>> watchArchivedMatches(String uid) {
    return _db
        .collection(FirestorePaths.matches)
        .where('userIds', arrayContains: uid)
        .where('isActive', isEqualTo: false)
        .orderBy('lastMessageAt', descending: true)
        .limit(_archivedLimit)
        .snapshots()
        .map((snap) {
          return [
            for (final doc in snap.docs)
              if (_matchFrom(doc).isDeletedAccountHistoryFor(uid))
                _listItem(_matchFrom(doc), uid),
          ];
        });
  }

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) {
    return _db
        .collection(FirestorePaths.matches)
        .where('userIds', arrayContains: uid)
        .where('isActive', isEqualTo: true)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => _listItem(_matchFrom(doc), uid))
              .toList(growable: false);
        });
  }

  @override
  Future<Match?> getMatch(String matchId) async {
    final snap = await _db.doc(FirestorePaths.match(matchId)).get();
    if (!snap.exists) {
      return null;
    }
    return _matchFrom(snap);
  }

  @override
  Stream<Match?> watchMatch(String matchId) {
    return _db
        .doc(FirestorePaths.match(matchId))
        .snapshots()
        .map((snap) => snap.exists ? _matchFrom(snap) : null)
        .handleError((Object error, StackTrace stackTrace) {
          // Missing/denied match reads must not crash profile photo UI.
        });
  }

  @override
  Future<void> markOpened(String matchId, String uid) async {
    await _db.doc(FirestorePaths.match(matchId)).update({
      'isNewFor.$uid': false,
      'unreadCounts.$uid': 0,
    });
  }

  @override
  Future<SwipeResultWrapper> recordSwipe({
    required String targetUserId,
    required String action,
  }) async {
    final data = await callable.invoke('recordSwipe', {
      'targetUserId': targetUserId,
      'action': action,
    });
    final matched = data['matched'] == true;
    Match? match;
    final matchId = data['matchId'] as String?;
    if (matched && matchId != null) {
      match = await getMatch(matchId);
    }
    return SwipeResultWrapper(matched: matched, match: match);
  }

  @override
  Stream<Set<String>> watchHiddenUserIds(String uid) {
    final blocks = _db
        .collection(FirestorePaths.blocks)
        .where('blockerId', isEqualTo: uid)
        .snapshots();
    return blocks.map((snap) {
      return snap.docs
          .map((doc) => doc.data()['blockedUserId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    });
  }
}

class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({
    required this.uidSource,
    FirebaseFirestore? firestore,
    StorageProvider? storage,
    E2eeChatService? e2ee,
  }) : _inner = ChatRepositoryImpl(
         dataSource: FirebaseChatDataSource(
           uidSource: uidSource,
           firestore: firestore,
         ),
         storage: storage ?? FirebaseStorageDataSource(),
         e2ee: e2ee ??
             E2eeChatService(
               storage: storage ?? FirebaseStorageDataSource(),
             ),
         uidSource: uidSource,
       );

  final AuthUidSource uidSource;
  final ChatRepository _inner;

  @override
  Future<bool> isE2eeActive({
    required String matchId,
    required String peerUid,
  }) {
    return _inner.isE2eeActive(matchId: matchId, peerUid: peerUid);
  }

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    return _inner.watchLatest(matchId, limit: limit);
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) {
    return _inner.loadOlder(matchId: matchId, before: before, limit: limit);
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) {
    return _inner.sendText(
      matchId: matchId,
      receiverId: receiverId,
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
    return _inner.sendImage(
      matchId: matchId,
      receiverId: receiverId,
      media: media,
      onProgress: onProgress,
    );
  }

  @override
  Future<ChatMessage> sendVoice({
    required String matchId,
    required String receiverId,
    required ChatMediaBytes media,
    void Function(double progress)? onProgress,
  }) {
    return _inner.sendVoice(
      matchId: matchId,
      receiverId: receiverId,
      media: media,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> deleteMessage({
    required String matchId,
    required String messageId,
  }) {
    return _inner.deleteMessage(matchId: matchId, messageId: messageId);
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) {
    return _inner.markDelivered(matchId, messages);
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) {
    return _inner.markRead(matchId, messages);
  }

  @override
  Future<void> setTyping({required String matchId, required bool isTyping}) {
    return _inner.setTyping(matchId: matchId, isTyping: isTyping);
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return _inner.watchTyping(matchId);
  }
}

class FirebaseSafetyRepository implements SafetyRepository {
  FirebaseSafetyRepository({
    required this.callable,
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable callable;
  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  @override
  Future<void> unmatch({required String matchId}) {
    return callable.invoke('unmatchUser', {'matchId': matchId});
  }

  @override
  Future<void> blockUser({required String userId, String? matchId}) {
    return callable.invoke('blockUser', {'userId': userId, 'matchId': matchId});
  }

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  }) {
    return callable.invoke('reportUser', {
      'userId': userId,
      'reason': reason,
      'matchId': matchId,
      'messageId': messageId,
      'description': description,
    });
  }

  @override
  Future<bool> isBlockedPair(String uidA, String uidB) async {
    if (uidA.isEmpty || uidB.isEmpty || uidA == uidB) {
      return false;
    }
    final docs = await Future.wait([
      _db.doc(FirestorePaths.block(SafetyPolicy.blockId(blockerId: uidA, blockedUserId: uidB))).get(),
      _db.doc(FirestorePaths.block(SafetyPolicy.blockId(blockerId: uidB, blockedUserId: uidA))).get(),
      _db.doc(FirestorePaths.blockedUser(uidA, uidB)).get(),
      _db.doc(FirestorePaths.blockedUser(uidB, uidA)).get(),
    ]);
    return docs.any((doc) => doc.exists);
  }

  @override
  Stream<Set<String>> watchBlockedUserIds(String uid) {
    return _db
        .collection(FirestorePaths.blocks)
        .where('blockerId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          return snap.docs
              .map((doc) => doc.data()['blockedUserId'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
        });
  }
}

class FirebaseCallRepository implements CallRepository {
  FirebaseCallRepository({
    required this.callable,
    required this.uidSource,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BackendCallable callable;
  final AuthUidSource uidSource;
  final FirebaseFirestore _db;

  CallSession _from(DocumentSnapshot<Map<String, dynamic>> snap, {Map<String, dynamic>? extra}) {
    final data = {...?snap.data(), ...?extra};
    return CallSession(
      id: snap.id,
      matchId: data['matchId'] as String? ?? '',
      callerId: data['callerId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      lifecycle: _lifecycle(data['status'] as String?),
      createdAt: _time(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      livekitUrl: data['url'] as String?,
      token: data['token'] as String?,
      roomName: data['roomName'] as String?,
      remoteName: data['remoteName'] as String?,
      remotePhotoUrl: data['remotePhotoUrl'] as String?,
    );
  }

  CallLifecycle _lifecycle(String? status) {
    return switch (status) {
      'ringing' => CallLifecycle.ringing,
      'calling' => CallLifecycle.calling,
      'connecting' => CallLifecycle.connecting,
      'connected' => CallLifecycle.connected,
      'declined' => CallLifecycle.declined,
      'cancelled' => CallLifecycle.cancelled,
      'busy' => CallLifecycle.busy,
      'failed' => CallLifecycle.failed,
      'ended' || 'missed' => CallLifecycle.ended,
      _ => CallLifecycle.idle,
    };
  }

  @override
  Future<CallSession> createCall({
    required String matchId,
    required String receiverId,
  }) async {
    final data = await callable.invoke('createVideoCall', {
      'matchId': matchId,
      'receiverId': receiverId,
    });
    return CallSession(
      id: data['callId'] as String? ?? '',
      matchId: matchId,
      callerId: uidSource.currentUid ?? '',
      receiverId: receiverId,
      lifecycle: CallLifecycle.calling,
      createdAt: DateTime.now(),
      livekitUrl: data['url'] as String?,
      token: data['token'] as String?,
      roomName: data['roomName'] as String?,
    );
  }

  @override
  Future<CallSession> respond({
    required String callId,
    required bool accept,
  }) async {
    final data = await callable.invoke('respondToVideoCall', {
      'callId': callId,
      'accept': accept,
    });
    return CallSession(
      id: callId,
      matchId: data['matchId'] as String? ?? '',
      callerId: data['callerId'] as String? ?? '',
      receiverId: uidSource.currentUid ?? '',
      lifecycle: accept ? CallLifecycle.connecting : CallLifecycle.declined,
      createdAt: DateTime.now(),
      livekitUrl: data['url'] as String?,
      token: data['token'] as String?,
      roomName: data['roomName'] as String?,
    );
  }

  @override
  Future<void> end(String callId) {
    return callable.invoke('endVideoCall', {'callId': callId});
  }

  @override
  Future<void> expire(String callId) {
    return callable.invoke('expireVideoCall', {'callId': callId});
  }

  @override
  Stream<List<CallSession>> watchIncoming(String uid) {
    return _db
        .collection(FirestorePaths.calls)
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) => snap.docs.map(_from).toList(growable: false));
  }

  @override
  Stream<CallSession?> watchCall(String callId) {
    return _db.doc(FirestorePaths.call(callId)).snapshots().map((snap) {
      if (!snap.exists) {
        return null;
      }
      return _from(snap);
    });
  }
}

class FirebasePresenceRepository implements PresenceRepository {
  FirebasePresenceRepository([FirebaseFirestore? firestore])
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<PresenceWatch> watch(String uid) {
    return _db.doc(FirestorePaths.presence(uid)).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      return PresenceWatch(
        isOnline: data['isOnline'] == true,
        updatedAt: _time(data['updatedAt']),
        lastSeenAt: _time(data['lastSeenAt']),
      );
    });
  }

  @override
  Future<void> setOnline(String uid) {
    return _db.doc(FirestorePaths.presence(uid)).set({
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
      // Clear stale lastSeenAt so merge updates are not rejected by rules.
      'lastSeenAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setOffline(String uid) {
    return _db.doc(FirestorePaths.presence(uid)).set({
      'isOnline': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> heartbeat(String uid) {
    return _db.doc(FirestorePaths.presence(uid)).set({
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class FirebaseNotificationRepository implements NotificationRepository {
  FirebaseNotificationRepository({
    FirebaseFirestore? firestore,
    FirebaseMessagingDataSource? messaging,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ??
           FirebaseMessagingDataSource(firestore: firestore);

  final FirebaseFirestore _db;
  final FirebaseMessagingDataSource _messaging;

  NotificationPrefs _prefs(Map<String, dynamic>? data) {
    return NotificationPrefs(
      messageNotifications: data?['messageNotifications'] as bool? ?? true,
      matchNotifications: data?['matchNotifications'] as bool? ?? true,
      hideOnlineStatus: data?['hideOnlineStatus'] as bool? ?? false,
    );
  }

  @override
  Stream<NotificationPrefs> watchPrefs(String uid) {
    return _db.doc(FirestorePaths.notificationSettings(uid)).snapshots().map(
      (snap) => _prefs(snap.data()),
    );
  }

  @override
  Future<NotificationPrefs> loadPrefs(String uid) async {
    final snap = await _db.doc(FirestorePaths.notificationSettings(uid)).get();
    return _prefs(snap.data());
  }

  @override
  Future<void> savePrefs(String uid, NotificationPrefs prefs) {
    return _db.doc(FirestorePaths.notificationSettings(uid)).set({
      'messageNotifications': prefs.messageNotifications,
      'matchNotifications': prefs.matchNotifications,
      'hideOnlineStatus': prefs.hideOnlineStatus,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> registerToken(String uid, String token) {
    return _messaging.registerDevice(uid: uid, token: token);
  }

  @override
  Future<void> unregisterToken(String uid, String token) {
    return _messaging.unregisterDevice(uid: uid, token: token);
  }
}
