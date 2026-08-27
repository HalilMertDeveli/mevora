import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/domain/entities/matching_game_round.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hourly mode skips dwell and opens offer from round sync', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(),
      ),
      enforceOfferGates: true,
      hourlyGlobalMatchingGame: true,
      interval: const Duration(hours: 1),
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

    expect(controller.hourlyGlobalMatchingGame, isTrue);
    expect(controller.isOfferVisible, isTrue);
    expect(controller.roundInfo, isNotNull);
    expect(controller.roundInfo!.timezone, 'Europe/Istanbul');
  });

  test('hourly session submits to matching game and can match', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: MockRelationshipDataSource(),
      ),
      enforceOfferGates: false,
      hourlyGlobalMatchingGame: true,
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

  test('hourly backend not-found falls back to legacy dwell', () async {
    final controller = RelationshipController(
      repository: RelationshipRepositoryImpl(
        dataSource: _FailingHourlyRoundDataSource(),
      ),
      enforceOfferGates: true,
      hourlyGlobalMatchingGame: true,
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
    expect(controller.hourlyGlobalMatchingGame, isFalse);
  });
}

class _FailingHourlyRoundDataSource extends MockRelationshipDataSource {
  @override
  Future<MatchingGameRoundInfo> getMatchingGameRound() async {
    throw FirebaseFunctionsException(
      code: 'not-found',
      message: 'NOT_FOUND',
    );
  }
}
