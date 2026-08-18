import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/services/boost_activation_service.dart';

void main() {
  const service = BoostActivationService(duration: Duration(minutes: 30));
  final now = DateTime.utc(2026, 8, 18, 12);

  Boost boost({
    BoostStatus status = BoostStatus.active,
    DateTime? expiresAt,
  }) {
    return Boost(
      boostId: 'b1',
      userId: 'u1',
      productId: 'com.mevora.app.boost',
      purchaseId: 'p1',
      status: status,
      createdAt: now,
      startedAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(minutes: 30)),
    );
  }

  test('activates with configured duration from now', () {
    final decision = service.decide(now: now, currentActive: null);
    expect(decision.shouldActivate, isTrue);
    expect(decision.expiresAt, now.add(const Duration(minutes: 30)));
  });

  test('one active boost at a time', () {
    final decision = service.decide(now: now, currentActive: boost());
    expect(decision.shouldActivate, isFalse);
    expect(decision.alreadyActive, isTrue);
  });

  test('expiresAt in the past is treated as expired even if status is active', () {
    final expired = boost(expiresAt: now.subtract(const Duration(minutes: 1)));
    expect(service.isExpired(expired, now), isTrue);
    expect(service.activeBoost([expired], now), isNull);
    final decision = service.decide(now: now, currentActive: expired);
    expect(decision.shouldActivate, isTrue);
  });

  test('stacking flag can be enabled later without rewriting callers', () {
    const stacking = BoostActivationService(allowStacking: true);
    final decision = stacking.decide(now: now, currentActive: boost());
    expect(decision.shouldActivate, isTrue);
  });
}
