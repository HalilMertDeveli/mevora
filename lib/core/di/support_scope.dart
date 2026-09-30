import 'package:flutter/material.dart';
import 'package:mevora/core/di/moderation_status_scope.dart';
import 'package:mevora/core/di/support_services_factory.dart';
import 'package:mevora/features/moderation_status/domain/repositories/moderation_status_repository.dart';
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
  const SupportServices({required this.repository, this.moderationStatus});

  final SupportRepository repository;

  /// The member's moderation record and appeals ("Why is my account
  /// restricted?"). Lives beside support: both are how a member reaches
  /// Mevora about their own account.
  final ModerationStatusRepository? moderationStatus;
}

SupportServices createSupportServices() => SupportServices(
  repository: createSupportRepository(),
  moderationStatus: createModerationStatusRepository(),
);
