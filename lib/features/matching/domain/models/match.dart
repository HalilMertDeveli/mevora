enum MatchSource { mutualLike, relationshipTest }

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
    this.lastMessage,
    this.lastMessageAt,
    this.unmatchedBy,
    this.unmatchedAt,
    this.unreadCounts = const {},
    this.isNewFor = const {},
    this.participantNames = const {},
    this.participantPhotos = const {},
    this.source = MatchSource.mutualLike,
  });

  final String id;

  /// Exactly two Firebase UIDs.
  final List<String> userIds;
  final DateTime createdAt;
  final bool isActive;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? unmatchedBy;
  final DateTime? unmatchedAt;
  final Map<String, int> unreadCounts;
  final Map<String, bool> isNewFor;
  final Map<String, String> participantNames;
  final Map<String, String> participantPhotos;
  final MatchSource source;

  bool get isRelationshipTest => source == MatchSource.relationshipTest;

  String otherUserId(String uid) {
    return userIds.firstWhere(
      (id) => id != uid,
      orElse: () => userIds.last,
    );
  }

  String otherName(String uid) =>
      participantNames[otherUserId(uid)] ?? 'Mevora';

  String? otherPhoto(String uid) => participantPhotos[otherUserId(uid)];

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;

  bool isNewMatchFor(String uid) =>
      (isNewFor[uid] ?? (lastMessage == null)) && isActive;

  bool isParticipant(String uid) => userIds.contains(uid);

  Match copyWith({
    bool? isActive,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? unmatchedBy,
    DateTime? unmatchedAt,
    Map<String, int>? unreadCounts,
    Map<String, bool>? isNewFor,
    MatchSource? source,
  }) {
    return Match(
      id: id,
      userIds: userIds,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unmatchedBy: unmatchedBy ?? this.unmatchedBy,
      unmatchedAt: unmatchedAt ?? this.unmatchedAt,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      isNewFor: isNewFor ?? this.isNewFor,
      participantNames: participantNames,
      participantPhotos: participantPhotos,
      source: source ?? this.source,
    );
  }
}
