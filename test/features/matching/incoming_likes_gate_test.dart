import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/matching/data/repositories/mock_incoming_likes_repository.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';
import 'package:mevora/features/matching/presentation/controllers/incoming_likes_controller.dart';

void main() {
  test('free locked snapshot never exposes liker identities', () async {
    final controller = IncomingLikesController(
      repository: MockIncomingLikesRepository(
        locked: true,
        count: 4,
        items: const [
          IncomingLikerPreview(uid: 'secret', displayName: 'ShouldNotAppear'),
        ],
      ),
    );
    await controller.load();
    expect(controller.snapshot.locked, isTrue);
    expect(controller.snapshot.premiumRequired, isTrue);
    expect(controller.snapshot.count, 4);
    expect(controller.snapshot.incomingLikeCount, 4);
    expect(controller.snapshot.items, isEmpty);
    controller.dispose();
  });

  test('premium unlocked snapshot keeps real likers', () async {
    final controller = IncomingLikesController(
      repository: MockIncomingLikesRepository(
        locked: false,
        items: const [
          IncomingLikerPreview(uid: 'u1', displayName: 'Hilal', age: 34),
        ],
      ),
    );
    await controller.load();
    expect(controller.snapshot.locked, isFalse);
    expect(controller.snapshot.premiumRequired, isFalse);
    expect(controller.snapshot.isPremium, isTrue);
    expect(controller.snapshot.items.single.displayName, 'Hilal');
    controller.dispose();
  });
}
