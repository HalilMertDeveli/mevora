import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship/domain/entities/matching_game_round.dart';
import 'package:mevora/features/relationship/domain/entities/mevora_hour_phase.dart';
import 'package:mevora/features/relationship/data/datasources/mock_relationship_data_source.dart';
import 'package:mevora/features/relationship/data/repositories/relationship_repository_impl.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MatchingGameRoundInfo next hour wraps 23 → 00', () {
    const round = MatchingGameRoundInfo(
      roundId: '2026082723',
      status: 'OPEN',
      timezone: 'Europe/Istanbul',
      serverNowMs: 0,
      nextRoundAtMs: 1000,
      closesAtMs: 1000,
    );
    expect(round.displayHour, '23');
    expect(round.nextDisplayHour, '00');
    expect(round.isOpen, isTrue);
  });

  test('after dismiss live, phase becomes upcoming not dwell', () async {
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

    expect(controller.isOfferVisible, isTrue);
    expect(controller.mevoraHourPhase, MevoraHourPhase.live);

    await controller.dismissOffer();
    await pumpEventQueue();

    expect(controller.isOfferVisible, isFalse);
    expect(controller.mevoraHourPhase, MevoraHourPhase.upcoming);
    expect(controller.mevoraHourReminderEnabled, isFalse);
  });
}
