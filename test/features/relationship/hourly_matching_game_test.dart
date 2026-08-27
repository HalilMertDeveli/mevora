import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
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
}
