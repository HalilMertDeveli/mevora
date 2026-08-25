import 'package:mevora/features/matching/domain/models/incoming_likes.dart';

/// Demo/dev stub — locked responses never include identities.
class MockIncomingLikesRepository implements IncomingLikesRepository {
  MockIncomingLikesRepository({
    this.locked = true,
    this.count = 0,
    this.items = const [],
  });

  final bool locked;
  final int count;
  final List<IncomingLikerPreview> items;

  @override
  Future<IncomingLikesSnapshot> fetchIncomingLikes() async {
    if (locked) {
      return IncomingLikesSnapshot(
        locked: true,
        isPremium: false,
        premiumRequired: true,
        count: count,
      );
    }
    return IncomingLikesSnapshot(
      locked: false,
      isPremium: true,
      premiumRequired: false,
      count: count > 0 ? count : items.length,
      items: items,
    );
  }
}
