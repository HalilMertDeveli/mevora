import 'package:mevora/features/boost/domain/entities/boost.dart';

class BoostActivationDecision {
  const BoostActivationDecision._({
    required this.shouldActivate,
    this.alreadyActive = false,
    this.insufficientBalance = false,
    this.startedAt,
    this.expiresAt,
    this.extendBoostId,
  });

  factory BoostActivationDecision.activate({
    required DateTime startedAt,
    required DateTime expiresAt,
    String? extendBoostId,
  }) {
    return BoostActivationDecision._(
      shouldActivate: true,
      startedAt: startedAt,
      expiresAt: expiresAt,
      extendBoostId: extendBoostId,
    );
  }

  factory BoostActivationDecision.alreadyActive() {
    return const BoostActivationDecision._(
      shouldActivate: false,
      alreadyActive: true,
    );
  }

  factory BoostActivationDecision.insufficientBalance() {
    return const BoostActivationDecision._(
      shouldActivate: false,
      insufficientBalance: true,
    );
  }

  final bool shouldActivate;
  final bool alreadyActive;
  final bool insufficientBalance;
  final DateTime? startedAt;
  final DateTime? expiresAt;

  /// When set, extend this existing Boost document instead of creating another.
  final String? extendBoostId;
}

/// Server-side policy for granting Boost time.
///
/// Stacking adds [duration] onto remaining time. Duplicate store transactions
/// must be rejected before this service runs.
class BoostActivationService {
  const BoostActivationService({
    this.allowStacking = true,
    this.duration = const Duration(days: 7),
  });

  final bool allowStacking;
  final Duration duration;

  Boost? activeBoost(Iterable<Boost> boosts, DateTime now) {
    for (final boost in boosts) {
      if (boost.isActiveAt(now)) {
        return boost;
      }
    }
    return null;
  }

  /// Treats expiresAt < now as expired even if status is still `active`.
  bool isExpired(Boost boost, DateTime now) => !boost.isActiveAt(now);

  BoostActivationDecision decide({
    required DateTime now,
    Boost? currentActive,
    int balance = 1,
    Duration? duration,
    bool requireBalance = false,
  }) {
    final grant = duration ?? this.duration;
    if (grant <= Duration.zero) {
      return BoostActivationDecision.insufficientBalance();
    }
    final live =
        currentActive != null && currentActive.isActiveAt(now)
            ? currentActive
            : null;
    if (live != null && !allowStacking) {
      return BoostActivationDecision.alreadyActive();
    }
    if (requireBalance && balance < 1) {
      return BoostActivationDecision.insufficientBalance();
    }
    final base = live?.expiresAt ?? now;
    return BoostActivationDecision.activate(
      startedAt: live?.startedAt ?? now,
      expiresAt: base.add(grant),
      extendBoostId: live?.boostId,
    );
  }
}
