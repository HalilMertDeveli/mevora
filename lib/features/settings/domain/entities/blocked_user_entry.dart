class BlockedUserEntry {
  const BlockedUserEntry({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.blockedAt,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final DateTime? blockedAt;
}
