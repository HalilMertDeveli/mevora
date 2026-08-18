import 'package:mevora/features/boost/domain/entities/boost.dart';

class BoostActivationDecision {
  const BoostActivationDecision._({
    required this.shouldActivate,
    this.alreadyActive = false,
    this.startedAt,
    this.expiresAt,
  });

  factory BoostActivationDecision.activate({
    required DateTime startedAt,
    required DateTime expiresAt,
  }) {
    return BoostActivationDecision._(
      shouldActivate: true,
      startedAt: startedAt,
      expiresAt: expiresAt,
    );
  }

  factory BoostActivationDecision.alreadyActive() {
    return const BoostActivationDecision._(
      shouldActivate: false,
      alreadyActive: true,
    );
  }

  final bool shouldActivate;
  final bool alreadyActive;
  final DateTime? startedAt;
  final DateTime? expiresAt;
}

/// Server-side policy for turning a verified purchase into a Boost.
/// [allowStacking] is false for MVP; keep the flag so duration stacking can
/// be enabled later without rewriting callers.
class BoostActivationService {
  const BoostActivationService({
    this.allowStacking = false,
    this.duration = const Duration(minutes: 30),
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
  }) {
    if (currentActive != null &&
        currentActive.isActiveAt(now) &&
        !allowStacking) {
      return BoostActivationDecision.alreadyActive();
    }
    return BoostActivationDecision.activate(
      startedAt: now,
      expiresAt: now.add(duration),
    );
  }
}
