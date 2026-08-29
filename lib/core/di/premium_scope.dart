import 'package:flutter/widgets.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_purchase_repository.dart';

class PremiumScope extends InheritedWidget {
  const PremiumScope({
    super.key,
    required this.purchaseRepository,
    required super.child,
  });

  final PremiumPurchaseRepository purchaseRepository;

  static PremiumScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PremiumScope>();
  }

  @override
  bool updateShouldNotify(PremiumScope oldWidget) {
    return purchaseRepository != oldWidget.purchaseRepository;
  }
}
