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
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/pump_app.dart';

class _FakeProfileAnswers implements ProfileQuestionAnswerRepository {
  final _controller = StreamController<List<ProfileQuestionAnswer>>.broadcast();
  var syncCalls = 0;
  var watchCalls = 0;
  var partnerFetchCalls = 0;
  PartnerQuestionAnswersSnapshot partnerSnapshot =
      PartnerQuestionAnswersSnapshot.empty;

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) {
    watchCalls += 1;
    return _controller.stream;
  }

  @override
  Future<Result<PartnerQuestionAnswersSnapshot>> fetchPartnerAnswers(
    String partnerUid,
  ) async {
    partnerFetchCalls += 1;
    return Success(partnerSnapshot);
  }

  @override
  Future<Result<void>> syncFromMatching() async {
    syncCalls += 1;
    return const Success(null);
  }

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

void main() {
  testWidgets('owner empty state shows title, hint, and triggers sync', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final relationshipController = RelationshipController(
      repository: _FakeRelationshipRepo(),
    );
    addTearDown(relationshipController.dispose);
    final auth = _auth();
    addTearDown(auth.dispose);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      wrapWithApp(
        AuthScope(
          controller: auth,
          child: RelationshipScope(
            repository: _FakeRelationshipRepo(),
            profileAnswers: answers,
            controller: relationshipController,
            child: const ProfileQuestionAnswersSection(
              uid: 'user-1',
              isOwner: true,
              showEditAction: true,
            ),
          ),
        ),
        scaffold: false,
      ),
    );

    await tester.pump();
    answers.emit(const []);
    await tester.pump();
    await tester.pump();

    expect(answers.syncCalls, 1);
    expect(find.text(l10n.questionAnswersTitle), findsOneWidget);
    expect(find.text(l10n.questionAnswersEmpty), findsOneWidget);
    expect(find.text(l10n.questionAnswersEmptyHint), findsOneWidget);
    expect(find.text(l10n.profileAnswersEdit), findsOneWidget);
  });

  testWidgets('owner section shows resolved question and answer cards', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final relationshipController = RelationshipController(
      repository: _FakeRelationshipRepo(),
    );
    addTearDown(relationshipController.dispose);
    final auth = _auth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      wrapWithApp(
        AuthScope(
          controller: auth,
          child: RelationshipScope(
            repository: _FakeRelationshipRepo(),
            profileAnswers: answers,
            controller: relationshipController,
            child: const ProfileQuestionAnswersSection(
              uid: 'user-1',
              isOwner: true,
              previewLimit: 5,
            ),
          ),
        ),
        scaffold: false,
      ),
    );

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

    expect(find.textContaining('Coffee'), findsWidgets);
  });

  testWidgets('free peer sees question prompts with Premium lock, not answers', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    answers.partnerSnapshot = const PartnerQuestionAnswersSnapshot(
      locked: true,
      matchRequired: false,
      premiumRequired: true,
      isPremium: false,
      items: [
        ProfileQuestionAnswer(
          questionId: 'rq_001',
          answerId: '',
          isVisible: true,
          answerLocked: true,
        ),
      ],
    );
    final relationshipController = RelationshipController(
      repository: _FakeRelationshipRepo(),
    );
    addTearDown(relationshipController.dispose);
    final auth = _auth();
    addTearDown(auth.dispose);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      wrapWithApp(
        AuthScope(
          controller: auth,
          child: RelationshipScope(
            repository: _FakeRelationshipRepo(),
            profileAnswers: answers,
            controller: relationshipController,
            child: const ProfileQuestionAnswersSection(
              uid: 'peer-1',
              requireMatch: false,
              previewLimit: 5,
            ),
          ),
        ),
        scaffold: false,
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.questionAnswersPremiumLockedMessage), findsOneWidget);
    expect(find.text(l10n.questionAnswersPremiumUnlockCta), findsWidgets);
    expect(find.text(l10n.questionAnswersPremiumAnswerHidden), findsOneWidget);
    expect(find.textContaining('Coffee'), findsWidgets);
    // Answer option labels must not appear for free peers.
    expect(find.textContaining('"'), findsNothing);
    // Peer path must use CF fetch — never Firestore watchAnswers.
    expect(answers.partnerFetchCalls, greaterThan(0));
    expect(answers.watchCalls, 0);
  });

  testWidgets('premium peer sees unlocked question and answer', (tester) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    answers.partnerSnapshot = const PartnerQuestionAnswersSnapshot(
      locked: false,
      matchRequired: false,
      premiumRequired: false,
      isPremium: true,
      items: [
        ProfileQuestionAnswer(
          questionId: 'rq_001',
          answerId: 'a',
          isVisible: true,
        ),
      ],
    );
    final relationshipController = RelationshipController(
      repository: _FakeRelationshipRepo(),
    );
    addTearDown(relationshipController.dispose);
    final auth = _auth();
    addTearDown(auth.dispose);
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      wrapWithApp(
        AuthScope(
          controller: auth,
          child: RelationshipScope(
            repository: _FakeRelationshipRepo(),
            profileAnswers: answers,
            controller: relationshipController,
            child: const ProfileQuestionAnswersSection(
              uid: 'peer-1',
              requireMatch: false,
              previewLimit: 5,
            ),
          ),
        ),
        scaffold: false,
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.questionAnswersPremiumLockedMessage), findsNothing);
    expect(find.text(l10n.questionAnswersPremiumAnswerHidden), findsNothing);
    expect(find.textContaining('Coffee'), findsWidgets);
    expect(find.textContaining('"'), findsWidgets);
    expect(answers.partnerFetchCalls, greaterThan(0));
    expect(answers.watchCalls, 0);
  });
}
