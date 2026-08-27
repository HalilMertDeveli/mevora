import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';
import 'package:mevora/features/relationship/domain/entities/matching_game_round.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new user gets immediate initial test — not dwell, not hourly join', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(),
      ),
      enforceOfferGates: true,
      hourlyGlobalMatchingGame: true,
      legacyDwellOffersEnabled: false,
      interval: const Duration(hours: 1),
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.start();
    controller.setDiscoveryVisible(true);
    await pumpEventQueue();

    expect(controller.needsInitialPersonalityTest, isTrue);
    expect(controller.isOfferVisible, isTrue);
    expect(controller.isInitialOffer, isTrue);
    expect(controller.offerKind, RelationshipOfferKind.initial);

    await controller.acceptOffer();
    await pumpEventQueue();
    expect(controller.currentQuestion, isNotNull);
  });

  test('legacy dwell 3/5/10 minutes never opens offer when disabled', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(matchingEventCount: 2),
      ),
      enforceOfferGates: true,
      hourlyGlobalMatchingGame: false,
      legacyDwellOffersEnabled: false,
      interval: const Duration(minutes: 3),
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.start();
    controller.setDiscoveryVisible(true);
    await pumpEventQueue();

    controller.debugElapse(const Duration(minutes: 3));
    await pumpEventQueue();
    expect(controller.isOfferVisible, isFalse);

    controller.debugElapse(const Duration(minutes: 5));
    await pumpEventQueue();
    expect(controller.isOfferVisible, isFalse);

    controller.debugElapse(const Duration(minutes: 10));
    await pumpEventQueue();
    expect(controller.isOfferVisible, isFalse);
  });

  test('after initial completion hourly mode opens Mevora Hour offer', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(matchingEventCount: 1),
      ),
      enforceOfferGates: true,
      hourlyGlobalMatchingGame: true,
      legacyDwellOffersEnabled: false,
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.start();
    controller.setDiscoveryVisible(true);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();

    expect(controller.needsInitialPersonalityTest, isFalse);
    expect(controller.initialPersonalityTestCompleted, isTrue);
    expect(controller.hourlyGlobalMatchingGame, isTrue);
    expect(controller.isOfferVisible, isTrue);
    expect(controller.isHourlyOffer, isTrue);
    expect(controller.roundInfo, isNotNull);
    expect(controller.roundInfo!.timezone, 'Europe/Istanbul');
  });

  test('hourly session submits to matching game and can match', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(matchingEventCount: 1),
      ),
      enforceOfferGates: false,
      hourlyGlobalMatchingGame: true,
      legacyDwellOffersEnabled: false,
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.start();
    controller.setDiscoveryVisible(true);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();

    expect(controller.isOfferVisible, isTrue);
    await controller.acceptOffer();
    await pumpEventQueue();
    expect(controller.currentQuestion, isNotNull);

    while (controller.currentQuestion != null) {
      await controller.answer(controller.currentQuestion!.answers.first.id);
      await pumpEventQueue();
    }

    expect(controller.isResultVisible || controller.waitingForRoundResult, isTrue);
  });

  test('hourly backend not-found does NOT fall back to legacy dwell', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: _FailingHourlyRoundDataSource(matchingEventCount: 1),
      ),
      enforceOfferGates: true,
      hourlyGlobalMatchingGame: true,
      legacyDwellOffersEnabled: false,
      interval: const Duration(seconds: 1),
    );
    addTearDown(() {
      controller.pause();
      controller.dispose();
    });

    await controller.start();
    controller.setDiscoveryVisible(true);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();

    expect(controller.hourlyBackendReady, isFalse);
    expect(controller.hourlyUnavailable, isTrue);
    expect(controller.isOfferVisible, isFalse);

    controller.debugElapse(const Duration(minutes: 3));
    await pumpEventQueue();
    expect(controller.isOfferVisible, isFalse);
  });
}

class _FailingHourlyRoundDataSource extends MockRelationshipDataSource {
  _FailingHourlyRoundDataSource({super.matchingEventCount});

  @override
  Future<MatchingGameRoundInfo> getMatchingGameRound() async {
    throw FirebaseFunctionsException(
      code: 'not-found',
      message: 'NOT_FOUND',
    );
  }
}
