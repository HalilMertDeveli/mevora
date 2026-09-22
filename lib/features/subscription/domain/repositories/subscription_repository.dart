import 'package:mevora/features/subscription/domain/entities/subscription_lifecycle.dart';

/// Observed Premium entitlement.
///
/// [isPremium] is the effective answer for the current moment; the remaining
/// fields describe why, so UI can later say "renews on", "ends on" or
/// "payment problem" without inventing a second source of truth.
class PremiumStatus {
  const PremiumStatus({
    this.isPremium = false,
    this.expiresAt,
    this.lifecycle = SubscriptionLifecycle.none,
    this.accessUntil,
    this.graceUntil,
    this.autoRenewing = false,
    this.platform,
    this.productId,
  });

  /// No entitlement. The safe default everywhere.
  static const PremiumStatus free = PremiumStatus();

  final bool isPremium;
  final DateTime? expiresAt;
  final SubscriptionLifecycle lifecycle;

  /// When access lapses if nothing renews it. Null means no known deadline.
  final DateTime? accessUntil;
  final DateTime? graceUntil;
  final bool autoRenewing;
  final String? platform;
  final String? productId;

  /// Auto-renew is off but the paid period has not run out yet.
  bool get isCancelledButActive =>
      isPremium && lifecycle == SubscriptionLifecycle.cancelled;

  /// The store is retrying payment; access is on borrowed time.
  bool get isInGracePeriod =>
      isPremium &&
      (lifecycle == SubscriptionLifecycle.gracePeriod ||
          lifecycle == SubscriptionLifecycle.billingRetry);
}

/// Entitlement stream. Billing UI is separate; this only observes status.
abstract class SubscriptionRepository {
  Stream<PremiumStatus> watch();
}

class DisabledSubscriptionRepository implements SubscriptionRepository {
  const DisabledSubscriptionRepository();

  @override
  Stream<PremiumStatus> watch() => Stream.value(PremiumStatus.free);
}
