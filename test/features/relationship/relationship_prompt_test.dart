import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/presentation/pages/matches_page.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/domain/services/relationship_compatibility_key.dart';
import 'package:mevora/features/relationship/domain/services/relationship_question_sets.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_question_card.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

RelationshipController _controller({
  RelationshipRepository? repository,
  Duration interval = AppDurations.relationshipPrompt,
  bool enforceOfferGates = true,
}) {
  final controller = RelationshipController(
    repository:
        repository ??
        RelationshipRepositoryImpl(dataSource: MockRelationshipDataSource()),
    interval: interval,
    enforceOfferGates: enforceOfferGates,
  );
  addTearDown(() {
    controller.pause();
    controller.dispose();
  });
  return controller;
}

void main() {
  test('first unanswered set is the first three catalog questions', () {
    final questions = RelationshipQuestionSets.nextUnanswered({});
    expect(questions, isNotNull);
    expect(questions!.map((item) => item.id), ['rq_001', 'rq_002', 'rq_003']);
    expect(
      RelationshipCompatibilityKey.canonical({
        'rq_003': 'c',
        'rq_001': 'a',
        'rq_002': 'b',
      }),
      'rq_001:a|rq_002:b|rq_003:c',
    );
  });

  testWidgets('discovery dwell with zero matches opens the test offer', (
    tester,
  ) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.setNormalMatchCount(0);
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isTrue);
    expect(controller.currentQuestion, isNull);
    controller.pause();
  });

  testWidgets('hidden discovery does not open the test offer', (
    tester,
  ) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(false);
    controller.setNormalMatchCount(0);
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isFalse);
    controller.pause();
  });

  testWidgets('a normal match blocks the relationship test offer', (
    tester,
  ) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.setNormalMatchCount(1);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isFalse);
    controller.pause();
  });

  testWidgets('debug bypass still offers the test when a match exists', (
    tester,
  ) async {
    final controller = _controller(enforceOfferGates: false);
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.setNormalMatchCount(2);
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isTrue);
    controller.pause();
  });

  testWidgets('later dismisses the offer without opening questions', (
    tester,
  ) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    await controller.dismissOffer();
    expect(controller.isOfferVisible, isFalse);
    expect(controller.sessionLocked, isFalse);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isFalse);
    controller.pause();
  });

  testWidgets('accepting the offer loads three unanswered questions', (
    tester,
  ) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    await controller.acceptOffer();
    expect(controller.sessionLength, 3);
    expect(controller.currentQuestion!.id, 'rq_001');
    controller.pause();
  });

  testWidgets('an open offer blocks another trigger', (tester) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isTrue);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    expect(controller.isOfferVisible, isTrue);
    expect(controller.currentQuestion, isNull);
    controller.pause();
  });

  testWidgets('three matching answers surface the nearest candidate', (
    tester,
  ) async {
    final controller = _controller();
    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.recordDiscoveryActivity();
    controller.debugElapse(AppDurations.relationshipPrompt);
    await controller.acceptOffer();
    expect(await controller.answer('a'), isTrue);
    expect(await controller.answer('b'), isTrue);
    expect(await controller.answer('c'), isTrue);
    expect(controller.isResultVisible, isTrue);
    expect(controller.testResults.first.candidate.uid, 'rel-ada');
    expect(controller.testResults.first.alignedCount, 3);
    expect(controller.testResults.length, 1);
    expect(controller.testResults.first.matchId, isNotEmpty);
    controller.pause();
  });

  testWidgets('accepting a match pauses the survey for the matched cooldown', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 21, 12);
    final repository = RelationshipRepositoryImpl(
      dataSource: MockRelationshipDataSource(clock: () => now),
    );
    final controller = RelationshipController(
      repository: repository,
      interval: const Duration(minutes: 30),
      clock: () => now,
      enforceOfferGates: true,
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.setNormalMatchCount(0);
    controller.debugElapse(const Duration(minutes: 30));
    await controller.acceptOffer();
    expect(await controller.answer('a'), isTrue);
    expect(await controller.answer('b'), isTrue);
    expect(await controller.answer('c'), isTrue);
    expect(controller.isResultVisible, isTrue);

    await controller.acceptMatchResult();
    expect(controller.isResultVisible, isFalse);

    now = now.add(const Duration(minutes: 10));
    controller.debugElapse(const Duration(minutes: 30));
    expect(controller.isOfferVisible, isFalse);

    now = now.add(const Duration(minutes: 25));
    controller.debugElapse(Duration.zero);
    expect(controller.isOfferVisible, isTrue);
  });

  testWidgets('closing results without a match retries after 3 minutes', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 21, 12);
    final repository = RelationshipRepositoryImpl(
      dataSource: MockRelationshipDataSource(clock: () => now),
    );
    final controller = RelationshipController(
      repository: repository,
      interval: const Duration(minutes: 30),
      clock: () => now,
      enforceOfferGates: true,
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.refreshAnswered();
    controller.setDiscoveryVisible(true);
    controller.setNormalMatchCount(0);
    controller.debugElapse(const Duration(minutes: 30));
    await controller.acceptOffer();
    expect(await controller.answer('a'), isTrue);
    expect(await controller.answer('b'), isTrue);
    expect(await controller.answer('c'), isTrue);

    await controller.dismissResults();
    now = now.add(const Duration(minutes: 2));
    controller.debugElapse(Duration.zero);
    expect(controller.isOfferVisible, isFalse);

    now = now.add(const Duration(minutes: 2));
    controller.debugElapse(Duration.zero);
    expect(controller.isOfferVisible, isTrue);
  });

  testWidgets('debug interval is 30 seconds outside release', (tester) async {
    expect(
      RelationshipQuestionConfig.debugInterval,
      const Duration(seconds: 30),
    );
    expect(
      RelationshipQuestionConfig.productionInterval,
      const Duration(minutes: 30),
    );
    expect(
      RelationshipQuestionConfig.declinedCooldown,
      const Duration(minutes: 3),
    );
    expect(
      RelationshipQuestionConfig.matchedCooldown,
      const Duration(minutes: 30),
    );
    expect(RelationshipQuestionConfig.interval, const Duration(seconds: 30));
  });

  testWidgets('question card shows three answers and session progress', (
    tester,
  ) async {
    final question = RelationshipQuestionCatalog.questions.first;
    await tester.pumpWidget(
      wrapWithApp(
        RelationshipQuestionCard(
          question: question,
          answeredCount: 1,
          totalCount: 3,
          onAnswer: (_) {},
        ),
      ),
    );
    expect(find.text('What do you think about relationships?'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text(question.answers[0].labelEn), findsOneWidget);
  });

  testWidgets('offer card uses the relationship test copy', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        RelationshipTestOfferCard(onStart: () {}, onLater: () {}),
      ),
    );
    expect(find.text(_l10n.relationshipTestHeadline), findsOneWidget);
    expect(find.text(_l10n.relationshipTestStart), findsOneWidget);
    expect(find.text(_l10n.relationshipTestLater), findsOneWidget);
  });

  testWidgets('result card shows the nearest match and profile action', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        RelationshipTestResultCard(
          results: const [
            RelationshipMatchSuggestion(
              candidate: DiscoveryCandidate(
                uid: 'rel-ada',
                displayName: 'Ada',
                age: 27,
                photos: [],
                city: 'Ankara',
                distanceKm: 1.4,
                distanceLabel: '1.4 km',
              ),
              score: 100,
              sharedQuestionCount: 3,
              alignedCount: 3,
              matchId: 'rel-ada_self',
            ),
          ],
          onDismiss: () {},
        ),
      ),
    );
    expect(find.text(_l10n.relationshipTestDoneTitle), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text(_l10n.relationshipTestViewProfile), findsOneWidget);
    expect(find.text(_l10n.relationshipTestOpenChat), findsOneWidget);
  });

  testWidgets('matches tile shows a relationship test badge', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        MatchListTile(
          item: MatchListItem(
            match: Match(
              id: 'rel-ada_self',
              userIds: const ['rel-ada', 'self'],
              createdAt: DateTime.utc(2026, 8, 21),
              isActive: true,
              source: MatchSource.relationshipTest,
              participantNames: const {'rel-ada': 'Ada'},
            ),
            otherUserId: 'rel-ada',
            name: 'Ada',
          ),
          currentUid: 'self',
        ),
      ),
    );
    expect(find.textContaining('Relationship Test'), findsOneWidget);
  });

  testWidgets('host timer shows the offer without swiping', (tester) async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(),
      ),
      interval: const Duration(seconds: 2),
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });
    await tester.pumpWidget(
      wrapWithApp(
        RelationshipPromptHost(
          controller: controller,
          discoveryVisible: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_l10n.relationshipTestStart), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(controller.isOfferVisible, isTrue);
    expect(find.text(_l10n.relationshipTestStart), findsOneWidget);
    expect(find.text(_l10n.relationshipTestHeadline), findsOneWidget);
    controller.pause();
  });
}
