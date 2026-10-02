import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_access.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/pump_app.dart';

const _answer = ProfileQuestionAnswer(
  questionId: 'rq_001',
  answerId: 'a',
  isVisible: true,
);

/// What each member has stored. A missing member answers with an error, the
/// way a list the viewer may not read does.
class _Answers implements ProfileQuestionAnswerRepository {
  _Answers(this.byUid);

  final Map<String, List<ProfileQuestionAnswer>> byUid;
  final watched = <String>[];

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) {
    watched.add(uid);
    final stored = byUid[uid];
    if (stored == null) {
      return Stream.error(StateError('permission-denied'));
    }
    return Stream.value(
      stored.where((item) => !visibleOnly || item.isVisible).toList(),
    );
  }

  @override
  Future<Result<void>> syncFromMatching() async => const Success(null);

  @override
  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  }) async => const Success(null);
}

class _FakeRelationshipRepo implements RelationshipRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SilentLogger implements AppLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AuthController _auth() {
  const user = AuthUser(id: 'viewer');
  final controller = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: FakeUserDocumentRepository(),
    logger: _SilentLogger(),
  );
  controller.user = user;
  controller.status = const Authenticated(user);
  return controller;
}

Future<void> _pump(WidgetTester tester, _Answers answers, String uid) async {
  final auth = _auth();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    wrapWithApp(
      AuthScope(
        controller: auth,
        child: RelationshipScope(
          repository: _FakeRelationshipRepo(),
          profileAnswers: answers,
          child: MatchedProfileAnswersAvailability(
            uid: uid,
            builder: (context, available) =>
                Text(available ? 'entry point' : 'nothing offered'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(ProfileQuestionAnswerAccess.forgetVisibleAnswers);

  Future<bool> has(_Answers answers, String profileUid) {
    return ProfileQuestionAnswerAccess.hasVisibleAnswers(
      answers: answers,
      viewerUid: 'viewer',
      profileUid: profileUid,
    );
  }

  group('whether a matched member has answers to show', () {
    test('yes with at least one visible answer', () async {
      final answers = _Answers({
        'ada': const [_answer],
      });
      expect(await has(answers, 'ada'), isTrue);
    });

    test('no without any, or with only hidden ones', () async {
      final answers = _Answers({
        'empty': const [],
        'hidden': const [
          ProfileQuestionAnswer(
            questionId: 'rq_001',
            answerId: 'a',
            isVisible: false,
          ),
        ],
      });
      expect(await has(answers, 'empty'), isFalse);
      expect(await has(answers, 'hidden'), isFalse);
    });

    test('is looked up once per member', () async {
      final answers = _Answers({
        'ada': const [_answer],
      });
      await has(answers, 'ada');
      await has(answers, 'ada');
      expect(answers.watched, ['ada']);
    });

    test('an unreadable list is "no" and is asked again next time', () async {
      final answers = _Answers({});
      expect(await has(answers, 'stranger'), isFalse);

      answers.byUid['stranger'] = const [_answer];
      expect(await has(answers, 'stranger'), isTrue);
    });

    test('never for an empty id', () async {
      final answers = _Answers({
        '': const [_answer],
      });
      expect(await has(answers, ''), isFalse);
      expect(answers.watched, isEmpty);
    });
  });

  testWidgets('offers the entry point only when there are answers behind it', (
    tester,
  ) async {
    final answers = _Answers({
      'ada': const [_answer],
      'empty': const [],
    });

    await _pump(tester, answers, 'empty');
    expect(find.text('nothing offered'), findsOneWidget);

    await _pump(tester, answers, 'ada');
    expect(find.text('entry point'), findsOneWidget);
  });
}
