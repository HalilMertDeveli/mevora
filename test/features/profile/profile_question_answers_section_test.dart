import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/matching/data/firebase/firebase_social_data.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_match_firestore.dart';
import '../../helpers/pump_app.dart';

class _FakeProfileAnswers implements ProfileQuestionAnswerRepository {
  final _controller = StreamController<List<ProfileQuestionAnswer>>.broadcast();
  var syncCalls = 0;

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) => _controller.stream;

  @override
  Future<Result<void>> syncFromMatching() async {
    syncCalls += 1;
    return const Success(null);
  }

  @override
  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  }) async => const Success(null);

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

class _NoBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async => const {};
}

/// Sends only the single-match listen to [remote], so SocialScope's inbox
/// listener does not need a Firestore query fake.
class _SingleMatchRepository implements MatchRepository {
  _SingleMatchRepository(this.remote);

  final MatchRepository remote;

  @override
  Stream<Match?> watchMatch(String matchId) => remote.watchMatch(matchId);

  @override
  Stream<List<MatchListItem>> watchMatches(String uid, {int? limit}) =>
      const Stream.empty();

  @override
  Future<Match?> getMatch(String matchId) async => null;

  @override
  Future<void> markOpened(String matchId, String uid) async {}
}

/// user-2's profile as user-1 sees it, through the Firebase match repository
/// the app wires in.
Widget _peerProfile({
  required AuthController auth,
  required _FakeProfileAnswers answers,
  required FakeMatchFirestore firestore,
}) {
  final uidSource = MutableAuthUidSource('user-1');
  final base = createGraphSocialServices(
    graph: InMemorySocialGraph(),
    uidSource: uidSource,
  );
  final services = SocialServices(
    uidSource: uidSource,
    matchRepository: _SingleMatchRepository(
      FirebaseMatchRepository(
        callable: _NoBackend(),
        uidSource: uidSource,
        firestore: firestore,
      ),
    ),
    likeRepository: base.likeRepository,
    chatRepository: base.chatRepository,
    safetyRepository: base.safetyRepository,
    presenceRepository: base.presenceRepository,
    callRepository: base.callRepository,
    videoCallService: base.videoCallService,
    videoCallProvider: base.videoCallProvider,
    notificationRepository: base.notificationRepository,
    discoveryExclusion: base.discoveryExclusion,
    incomingLikesRepository: base.incomingLikesRepository,
  );
  return SocialScope(
    services: services,
    child: wrapWithApp(
      AuthScope(
        controller: auth,
        child: RelationshipScope(
          repository: _FakeRelationshipRepo(),
          profileAnswers: answers,
          child: const ProfileQuestionAnswersSection(uid: 'user-2'),
        ),
      ),
    ),
  );
}

final _matchPath = FirestorePaths.match('user-1_user-2');

const _activeMatch = <String, dynamic>{
  'userIds': ['user-1', 'user-2'],
  'isActive': true,
};

const _visibleAnswer = ProfileQuestionAnswer(
  questionId: 'rq_001',
  answerId: 'a',
  isVisible: true,
);

void main() {
  group("another member's profile", () {
    testWidgets('an unmatched viewer gets the locked card, not a spinner', (
      tester,
    ) async {
      final answers = _FakeProfileAnswers();
      addTearDown(answers.dispose);
      final auth = _auth();
      addTearDown(auth.dispose);
      final firestore = FakeMatchFirestore();
      addTearDown(firestore.dispose);
      final l10n = lookupAppLocalizations(const Locale('en'));

      // firestore.rules (B-07) refuses the listen: the two are not matched.
      firestore.deny(_matchPath);
      await tester.pumpWidget(
        _peerProfile(auth: auth, answers: answers, firestore: firestore),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(l10n.questionAnswersMatchRequired), findsOneWidget);
      expect(find.text(l10n.questionAnswersTitle), findsOneWidget);
    });

    testWidgets('a matched viewer still sees the answers', (tester) async {
      final answers = _FakeProfileAnswers();
      addTearDown(answers.dispose);
      final auth = _auth();
      addTearDown(auth.dispose);
      final firestore = FakeMatchFirestore();
      addTearDown(firestore.dispose);
      final l10n = lookupAppLocalizations(const Locale('en'));

      firestore.emit(_matchPath, _activeMatch);
      await tester.pumpWidget(
        _peerProfile(auth: auth, answers: answers, firestore: firestore),
      );
      await tester.pump();
      await tester.pump();
      answers.emit(const [_visibleAnswer]);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Coffee'), findsWidgets);
      expect(find.text(l10n.questionAnswersMatchRequired), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the answers lock again once the match can no longer be read', (
      tester,
    ) async {
      final answers = _FakeProfileAnswers();
      addTearDown(answers.dispose);
      final auth = _auth();
      addTearDown(auth.dispose);
      final firestore = FakeMatchFirestore();
      addTearDown(firestore.dispose);
      final l10n = lookupAppLocalizations(const Locale('en'));

      firestore.emit(_matchPath, _activeMatch);
      await tester.pumpWidget(
        _peerProfile(auth: auth, answers: answers, firestore: firestore),
      );
      await tester.pump();
      await tester.pump();
      answers.emit(const [_visibleAnswer]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Coffee'), findsWidgets);

      firestore.deny(_matchPath);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Coffee'), findsNothing);
      expect(find.text(l10n.questionAnswersMatchRequired), findsOneWidget);
    });
  });

  testWidgets('owner empty state shows title, hint, and triggers sync', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
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
    // With nothing to show there is no card: its Edit button used to open an
    // empty page with nothing to do on it.
    expect(find.text(l10n.questionAnswersTitle), findsNothing);
    expect(find.text(l10n.questionAnswersEmpty), findsNothing);
    expect(find.text(l10n.profileAnswersEdit), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('owner section shows resolved question and answer cards', (
    tester,
  ) async {
    final answers = _FakeProfileAnswers();
    addTearDown(answers.dispose);
    final auth = _auth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      wrapWithApp(
        AuthScope(
          controller: auth,
          child: RelationshipScope(
            repository: _FakeRelationshipRepo(),
            profileAnswers: answers,
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
}
