import 'package:flutter/widgets.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';

class RelationshipScope extends InheritedWidget {
  const RelationshipScope({
    super.key,
    required this.repository,
    required this.profileAnswers,
    required this.controller,
    required super.child,
  });

  final RelationshipRepository repository;
  final ProfileQuestionAnswerRepository profileAnswers;
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

  static ProfileQuestionAnswerRepository? profileAnswersOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<RelationshipScope>()
        ?.profileAnswers;
  }

  static RelationshipController? controllerOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RelationshipScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(RelationshipScope oldWidget) {
    return repository != oldWidget.repository ||
        profileAnswers != oldWidget.profileAnswers ||
        controller != oldWidget.controller;
  }
}
