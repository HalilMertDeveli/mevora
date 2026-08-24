import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';

import '../../helpers/pump_app.dart';

class _FakeProfileAnswers implements ProfileQuestionAnswerRepository {
  final _controller = StreamController<List<ProfileQuestionAnswer>>.broadcast();

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) =>
      _controller.stream;

  @override
  Future<Result<void>> syncFromMatching() async => const Success(null);

  @override
  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  }) async =>
      const Success(null);

  void emit(List<ProfileQuestionAnswer> value) => _controller.add(value);

  void dispose() => _controller.close();
}

class _FakeRelationshipRepo implements RelationshipRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ProfileQuestionAnswersSection mounts without inherited scope crash', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final relationshipController = RelationshipController(
      repository: _FakeRelationshipRepo(),
    );
    addTearDown(relationshipController.dispose);

    await tester.pumpWidget(
      wrapWithApp(
        RelationshipScope(
          repository: _FakeRelationshipRepo(),
          profileAnswers: answers,
          controller: relationshipController,
          child: const ProfileQuestionAnswersSection(
            uid: 'user-1',
            isOwner: true,
          ),
        ),
        scaffold: false,
      ),
    );

    await tester.pump();
    answers.emit(const []);
    await tester.pump();

    expect(find.byType(ProfileQuestionAnswersSection), findsOneWidget);
  });
}
