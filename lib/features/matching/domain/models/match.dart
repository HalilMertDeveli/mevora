import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';

enum MatchSource { mutualLike, relationshipTest }

/// How a thread should be presented, derived from the match document alone.
///
/// The backend has no dedicated "counterpart deleted" flag. It does, however,
/// always stamp [Match.endedReason] when a thread ends by a user action:
/// 'unmatch' for unmatch and 'block' for block. Account deletion deactivates the
/// match without an endedReason (it only anonymises the participant fields), so
/// an inactive thread ended by the *other* participant with no endedReason is a
/// deleted account. That is a structural signal, not a label comparison.
enum MatchThreadState {
  /// Normal, messageable match.
  active,

  /// Counterpart deleted their account: retained, read-only conversation.
  deletedAccountHistory,

  /// Unmatched, blocked, or otherwise ended — not surfaced as history.
  inactiveOther,
}

MatchSource matchSourceFrom(Object? raw, {Object? matchType}) {
  if (raw == 'relationship_test' || matchType == 'relationship') {
    return MatchSource.relationshipTest;
  }
  return MatchSource.mutualLike;
}

class Match {
  const Match({
    required this.id,
    required this.userIds,
    required this.createdAt,
    required this.isActive,
    this.matchedAt,
    this.lastMessage,
    this.lastMessageAt,
    this.unmatchedBy,
    this.unmatchedAt,
    this.endedReason,
    this.unreadCounts = const {},
    this.isNewFor = const {},
    this.participantNames = const {},
    this.participantPhotos = const {},
    this.participantVerified = const {},
    this.source = MatchSource.mutualLike,
    this.compatibilitySnapshots = const {},
  });

  final String id;

  /// Exactly two Firebase UIDs.
  final List<String> userIds;
  final DateTime createdAt;
  final bool isActive;

  /// Canonical match time from Firestore (`matchedAt` or `createdAt`).
  DateTime get occurredAt => matchedAt ?? createdAt;

  final DateTime? matchedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? unmatchedBy;
  final DateTime? unmatchedAt;

  /// Why the thread ended: 'unmatch', 'block', or null. Account deletion
  /// leaves it null, which is what separates it from a user-initiated ending.
  final String? endedReason;
  final Map<String, int> unreadCounts;
  final Map<String, bool> isNewFor;
  final Map<String, String> participantNames;
  final Map<String, String> participantPhotos;
  final Map<String, bool> participantVerified;
  final MatchSource source;

  /// Per-participant snapshots written at mutual-match time (may be empty for legacy docs).
  final Map<String, CompatibilitySnapshot> compatibilitySnapshots;

  bool get isRelationshipTest => source == MatchSource.relationshipTest;

  CompatibilitySnapshot? compatibilityFor(String uid) =>
      compatibilitySnapshots[uid];

  String otherUserId(String uid) {
    return userIds.firstWhere(
      (id) => id != uid,
      orElse: () => userIds.last,
    );
  }

  String otherName(String uid) =>
      participantNames[otherUserId(uid)] ?? 'Mevora';

  String? otherPhoto(String uid) => participantPhotos[otherUserId(uid)];

  bool otherIsVerified(String uid) =>
      participantVerified[otherUserId(uid)] ?? false;

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;

  bool isNewMatchFor(String uid) =>
      (isNewFor[uid] ?? (lastMessage == null)) && isActive;

  bool isParticipant(String uid) => userIds.contains(uid);

  /// Classification used by both the match list and the chat screen.
  MatchThreadState threadStateFor(String uid) {
    if (isActive) {
      return MatchThreadState.active;
    }
    if (endedReason != null) {
      return MatchThreadState.inactiveOther;
    }
    // Deletion stamps unmatchedBy with the departing user's uid.
    final other = otherUserId(uid);
    if (unmatchedBy == null || unmatchedBy != other) {
      return MatchThreadState.inactiveOther;
    }
    return MatchThreadState.deletedAccountHistory;
  }

  /// True when this thread is a retained conversation with a deleted account.
  bool isDeletedAccountHistoryFor(String uid) =>
      threadStateFor(uid) == MatchThreadState.deletedAccountHistory;

  Match copyWith({
    bool? isActive,
    DateTime? matchedAt,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? unmatchedBy,
    DateTime? unmatchedAt,
    String? endedReason,
    Map<String, int>? unreadCounts,
    Map<String, bool>? isNewFor,
    MatchSource? source,
    Map<String, CompatibilitySnapshot>? compatibilitySnapshots,
  }) {
    return Match(
      id: id,
      userIds: userIds,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
      matchedAt: matchedAt ?? this.matchedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unmatchedBy: unmatchedBy ?? this.unmatchedBy,
      unmatchedAt: unmatchedAt ?? this.unmatchedAt,
      endedReason: endedReason ?? this.endedReason,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      isNewFor: isNewFor ?? this.isNewFor,
      participantNames: participantNames,
      participantPhotos: participantPhotos,
      participantVerified: participantVerified,
      source: source ?? this.source,
      compatibilitySnapshots:
          compatibilitySnapshots ?? this.compatibilitySnapshots,
    );
  }
}
