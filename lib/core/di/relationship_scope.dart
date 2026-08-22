import 'package:flutter/widgets.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';

class RelationshipScope extends InheritedWidget {
  const RelationshipScope({
    super.key,
    required this.repository,
    required this.controller,
    required super.child,
  });

  final RelationshipRepository repository;
  final RelationshipController controller;

  static RelationshipRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RelationshipScope>();
    assert(scope != null, 'RelationshipScope not found');
    return scope!.repository;
  }

  static RelationshipRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RelationshipScope>()
        ?.repository;
  }

  static RelationshipController? controllerOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RelationshipScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(RelationshipScope oldWidget) {
    return repository != oldWidget.repository ||
        controller != oldWidget.controller;
  }
}
