import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';

void main() {
  final now = DateTime.utc(2026, 8, 18, 12, 0);

  test('active boost remaining time uses expiresAt vs now', () {
    final boost = Boost(
      boostId: 'b1',
      userId: 'u1',
      productId: 'com.mevora.app.boost',
      purchaseId: 'p1',
      status: BoostStatus.active,
      createdAt: now,
      startedAt: now,
      expiresAt: now.add(const Duration(minutes: 12)),
    );
    expect(boost.isActiveAt(now), isTrue);
    expect(boost.remaining(now), const Duration(minutes: 12));
    expect(boost.isActiveAt(now.add(const Duration(minutes: 12))), isFalse);
    expect(boost.remaining(now.add(const Duration(minutes: 13))), Duration.zero);
  });

  test('cancelled or pending boosts are not active', () {
    final pending = Boost(
      boostId: 'b1',
      userId: 'u1',
      productId: 'com.mevora.app.boost',
      purchaseId: 'p1',
      status: BoostStatus.pending,
      createdAt: DateTime.utc(2026, 8, 18),
    );
    expect(pending.isActiveAt(now), isFalse);
  });
}
