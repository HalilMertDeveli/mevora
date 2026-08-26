class IncomingLikerPreview {
  const IncomingLikerPreview({
    required this.uid,
    required this.displayName,
    this.age,
    this.photoUrl,
    this.city,
    this.action = 'like',
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final int? age;
  final String? photoUrl;
  final String? city;
  final String action;
  final DateTime? createdAt;
}

/// Server-shaped payload from [getIncomingLikes].
///
/// When [locked] / [premiumRequired] is true, [items] is always empty —
/// identities were never sent to the client. UI may render anonymous blur
/// placeholders from [count] only.
class IncomingLikesSnapshot {
  const IncomingLikesSnapshot({
    required this.locked,
    required this.isPremium,
    required this.count,
    this.premiumRequired = true,
    this.items = const [],
  });

  final bool locked;
  final bool isPremium;
  final bool premiumRequired;
  final int count;
  final List<IncomingLikerPreview> items;

  int get incomingLikeCount => count;

  static const empty = IncomingLikesSnapshot(
    locked: true,
    isPremium: false,
    premiumRequired: true,
    count: 0,
  );
}

abstract class IncomingLikesRepository {
  Future<IncomingLikesSnapshot> fetchIncomingLikes();
}
