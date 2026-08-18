import 'package:flutter/widgets.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class BoostScope extends InheritedWidget {
  const BoostScope({
    super.key,
    required this.repository,
    required super.child,
    this.analytics,
  });

  final PurchaseRepository repository;
  final AnalyticsProvider? analytics;

  static BoostScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BoostScope>();
    assert(scope != null, 'BoostScope not found');
    return scope!;
  }

  static BoostScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BoostScope>();
  }

  @override
  bool updateShouldNotify(BoostScope oldWidget) {
    return repository != oldWidget.repository || analytics != oldWidget.analytics;
  }
}
