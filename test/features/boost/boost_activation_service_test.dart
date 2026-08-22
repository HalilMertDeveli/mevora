import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/services/boost_activation_service.dart';

void main() {
  const service = BoostActivationService(
    allowStacking: false,
    duration: Duration(minutes: 30),
  );
  final now = DateTime.utc(2026, 8, 18, 12);

  Boost boost({
    BoostStatus status = BoostStatus.active,
    DateTime? expiresAt,
  }) {
    return Boost(
      boostId: 'b1',
      userId: 'u1',
      productId: 'mevora_boost_7_days',
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

  test('one active boost at a time when stacking is disabled', () {
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

  test('stacking adds the new duration onto remaining time', () {
    const stacking = BoostActivationService(duration: Duration(days: 7));
    final remaining = now.add(const Duration(days: 5));
    final decision = stacking.decide(
      now: now,
      currentActive: boost(expiresAt: remaining),
      duration: const Duration(days: 7),
    );
    expect(decision.shouldActivate, isTrue);
    expect(decision.extendBoostId, 'b1');
    expect(decision.expiresAt, remaining.add(const Duration(days: 7)));
  });

  test('zero balance cannot activate when a wallet grant is required', () {
    final decision = service.decide(
      now: now,
      currentActive: null,
      balance: 0,
      requireBalance: true,
    );
    expect(decision.shouldActivate, isFalse);
    expect(decision.insufficientBalance, isTrue);
  });
}
