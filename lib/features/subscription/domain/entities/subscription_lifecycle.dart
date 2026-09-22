/// Shared subscription lifecycle vocabulary.
///
/// Mirrors the canonical backend contract in `functions/src/subscription`.
/// Google Play and Apple both map onto these states; nothing store-specific
/// belongs here.
enum SubscriptionLifecycle {
  /// Paid and renewing, or a manual grant.
  active('active'),

  /// Payment failed, the store granted a grace window, access is kept.
  gracePeriod('grace_period'),

  /// Payment failed and the store is retrying. Access continues only while a
  /// grace window is still open.
  billingRetry('billing_retry'),

  /// The paid period ended.
  expired('expired'),

  /// Auto-renew is off; the paid period still runs to its end.
  cancelled('cancelled'),

  /// Entitlement withdrawn by the store or by support.
  revoked('revoked'),

  /// Money returned; entitlement withdrawn immediately.
  refunded('refunded'),

  /// No subscription document, or one that could not be understood.
  none('none');

  const SubscriptionLifecycle(this.wireValue);

  /// The value stored in `users/{uid}/subscription/current`.
  final String wireValue;

  /// Fails safe: anything unrecognised becomes [SubscriptionLifecycle.none].
  static SubscriptionLifecycle fromWire(Object? value) {
    if (value is! String) {
      return SubscriptionLifecycle.none;
    }
    for (final lifecycle in SubscriptionLifecycle.values) {
      if (lifecycle.wireValue == value) {
        return lifecycle;
      }
    }
    return SubscriptionLifecycle.none;
  }
}
