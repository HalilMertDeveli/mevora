import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/data/datasources/firestore_relationship_answers_reader.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';
import 'package:mevora/features/settings/presentation/pages/profile_answers_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/pump_app.dart';

class _FakeProfileAnswers implements ProfileQuestionAnswerRepository {
  final _controller =
      StreamController<List<ProfileQuestionAnswer>>.broadcast();
  var syncCalls = 0;
  final visibility = <String, bool>{};

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) =>
      _controller.stream;

  @override
  Future<Result<void>> syncFromMatching() async {
    syncCalls += 1;
    return const Success(null);
  }

  @override
  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  }) async {
    visibility[questionId] = isVisible;
    return const Success(null);
  }

  void emit(List<ProfileQuestionAnswer> value) => _controller.add(value);

  void dispose() => _controller.close();
}

class _FakeRelationshipRepo implements RelationshipRepository {
  _FakeRelationshipRepo({
    this.saved = const {},
    this.delay = Duration.zero,
    this.failLoad = false,
  });

  Map<String, String> saved;
  final Duration delay;
  final bool failLoad;
  final List<(String, String)> saveCalls = [];

  @override
  Future<Result<Map<String, String>>> getSavedAnswers(String uid) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (failLoad) {
      return const Err(UnexpectedFailure('load-failed'));
    }
    return Success(Map<String, String>.from(saved));
  }

  @override
  Future<Result<RelationshipAnswerSnapshot>> saveAnswer({
    required String questionId,
    required String answerId,
  }) async {
    saveCalls.add((questionId, answerId));
    saved = {...saved, questionId: answerId};
    return Success(
      RelationshipAnswerSnapshot(
        answeredIds: saved.keys.toSet(),
        answerCount: saved.length,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SilentLogger implements AppLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AuthController _auth() {
  const user = AuthUser(id: 'user-1', email: 'a@b.com', displayName: 'Ada');
  final controller = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: FakeUserDocumentRepository(),
    logger: _SilentLogger(),
  );
  controller.user = user;
  controller.status = const Authenticated(user);
  return controller;
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required RelationshipRepository relationship,
  required _FakeProfileAnswers answers,
}) async {
  final relationshipController = RelationshipController(
    repository: relationship,
  );
  addTearDown(relationshipController.dispose);
  final auth = _auth();
  addTearDown(auth.dispose);

  await tester.pumpWidget(
    wrapWithApp(
      AuthScope(
        controller: auth,
        child: RelationshipScope(
          repository: relationship,
          profileAnswers: answers,
          controller: relationshipController,
          child: const ProfileAnswersPage(),
        ),
      ),
      scaffold: false,
    ),
  );
}

void main() {
  testWidgets('edit page leaves loading and shows empty state', (tester) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final relationship = _FakeRelationshipRepo();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pumpPage(tester, relationship: relationship, answers: answers);
    await tester.pump();
    answers.emit(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(l10n.questionAnswersEmpty), findsOneWidget);
    expect(answers.syncCalls, 1);
  });

  testWidgets('edit page loads own answers and allows changing choice', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final relationship = _FakeRelationshipRepo(
      saved: const {'rq_001': 'a'},
    );
    final question = RelationshipQuestionCatalog.byId('rq_001')!;
    final optionB = question.answers.firstWhere((item) => item.id == 'b');

    await _pumpPage(tester, relationship: relationship, answers: answers);
    await tester.pump();
    answers.emit(const [
      ProfileQuestionAnswer(
        questionId: 'rq_001',
        answerId: 'a',
        isVisible: true,
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining(question.promptFor('en').split('?').first),
        findsWidgets);

    await tester.tap(find.widgetWithText(MevoraChip, optionB.labelFor('en')));
    await tester.pump();
    await tester.pump();

    expect(relationship.saveCalls, [('rq_001', 'b')]);
    expect(relationship.saved['rq_001'], 'b');
  });

  testWidgets('edit page shows load error with retry instead of hanging', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final relationship = _FakeRelationshipRepo(failLoad: true);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pumpPage(tester, relationship: relationship, answers: answers);
    await tester.pump();
    answers.emit(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(l10n.questionAnswersLoadError), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
  });

  test('changing answer keeps questionId and replaces answerId', () async {
    final relationship = _FakeRelationshipRepo(saved: const {'rq_002': 'a'});
    final first = await relationship.saveAnswer(
      questionId: 'rq_002',
      answerId: 'b',
    );
    final second = await relationship.saveAnswer(
      questionId: 'rq_002',
      answerId: 'c',
    );
    expect(first.isSuccess, isTrue);
    expect(second.isSuccess, isTrue);
    expect(relationship.saved.keys.toList(), ['rq_002']);
    expect(relationship.saved['rq_002'], 'c');
    expect(relationship.saveCalls.length, 2);
  });

  test('answer reader prefers summary then collection fallback', () {
    expect(
      FirestoreRelationshipAnswersReader.preferSummaryOrCollection(
        summary: const {'rq_001': 'a'},
        collection: const {'rq_001': 'c'},
      ),
      {'rq_001': 'a'},
    );
    expect(
      FirestoreRelationshipAnswersReader.preferSummaryOrCollection(
        summary: const {},
        collection: const {'rq_010': 'b'},
      ),
      {'rq_010': 'b'},
    );
  });
}
