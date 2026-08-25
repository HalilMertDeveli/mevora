class PremiumStatus {
  const PremiumStatus({this.isPremium = false, this.expiresAt});

  final bool isPremium;
  final DateTime? expiresAt;
}

/// Entitlement stream. Billing UI is separate; this only observes status.
abstract class SubscriptionRepository {
  Stream<PremiumStatus> watch();
}

class DisabledSubscriptionRepository implements SubscriptionRepository {
  const DisabledSubscriptionRepository();

  @override
  Stream<PremiumStatus> watch() => Stream.value(const PremiumStatus());
}
