import 'dart:async';

class PremiumStatus {
  const PremiumStatus({this.isPremium = false});

  final bool isPremium;
}

/// Placeholder only. Do not build payments until the dating core is stable.
abstract class SubscriptionRepository {
  Stream<PremiumStatus> watch();
}

class DisabledSubscriptionRepository implements SubscriptionRepository {
  const DisabledSubscriptionRepository();

  @override
  Stream<PremiumStatus> watch() => Stream.value(const PremiumStatus());
}
