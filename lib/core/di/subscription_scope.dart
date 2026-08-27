import 'package:flutter/widgets.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class SubscriptionScope extends InheritedWidget {
  const SubscriptionScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final SubscriptionRepository repository;

  static SubscriptionRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SubscriptionScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(SubscriptionScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
