import 'package:flutter/material.dart';
import 'package:mevora/core/di/support_services_factory.dart';
import 'package:mevora/features/support/domain/repositories/support_repository.dart';

class SupportScope extends InheritedWidget {
  const SupportScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final SupportRepository repository;

  static SupportScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SupportScope>();
    assert(scope != null, 'SupportScope not found');
    return scope!;
  }

  static SupportScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SupportScope>();
  }

  @override
  bool updateShouldNotify(SupportScope oldWidget) {
    return oldWidget.repository != repository;
  }
}

class SupportServices {
  const SupportServices({required this.repository});

  final SupportRepository repository;
}

SupportServices createSupportServices() => SupportServices(
  repository: createSupportRepository(),
);
