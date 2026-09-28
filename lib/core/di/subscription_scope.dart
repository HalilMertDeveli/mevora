import 'package:flutter/widgets.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/subscription_controller.dart';

/// Single access point for Premium entitlement state.
///
/// Feature gates and, later, the paywall read from here. There is deliberately
/// no way to set entitlement through this scope — the backend owns it.
class SubscriptionScope extends InheritedNotifier<SubscriptionController> {
  const SubscriptionScope({
    super.key,
    required SubscriptionController controller,
    required this.repository,
    this.billing,
    required super.child,
  }) : super(notifier: controller);

  final SubscriptionRepository repository;

  /// How Premium is bought. Null when Premium is switched off. Nothing on
  /// this object can grant entitlement — it only opens the store.
  final PremiumBillingRepository? billing;

  static SubscriptionScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SubscriptionScope>();
    assert(scope != null, 'SubscriptionScope not found in the widget tree');
    return scope!;
  }

  static SubscriptionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SubscriptionScope>();
  }

  SubscriptionController get controller => notifier!;

  /// Billing for the paywall, or null when Premium is off. A null here is
  /// why the paywall is not offered rather than something to work around.
  static PremiumBillingRepository? billingOf(BuildContext context) {
    return maybeOf(context)?.billing;
  }

  /// Effective entitlement for the signed-in user. Rebuilds the caller when it
  /// changes. Free is the safe answer when the scope is absent — a widget tree
  /// without the scope must never look premium.
  static PremiumStatus statusOf(BuildContext context) {
    return maybeOf(context)?.controller.status ?? PremiumStatus.free;
  }

  static bool isPremiumOf(BuildContext context) => statusOf(context).isPremium;

  @override
  bool updateShouldNotify(SubscriptionScope oldWidget) {
    return repository != oldWidget.repository ||
        billing != oldWidget.billing ||
        super.updateShouldNotify(oldWidget);
  }
}
