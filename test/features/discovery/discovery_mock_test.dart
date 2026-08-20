import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/discovery/data/datasources/mock_discovery_data_source.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';

class _FixedUid implements AuthUidSource {
  const _FixedUid(this.currentUid);

  @override
  final String? currentUid;

  @override
  Stream<String?> watchUid() => Stream.value(currentUid);
}

void main() {
  group('MockDiscoveryRepository', () {
    test('provides 10 varied mock profiles', () async {
      final repo = MockDiscoveryRepository();
      final result = await repo.getCandidates(radius: DiscoveryRadius.km50);
      expect(result.isSuccess, isTrue);
      final candidates = result.valueOrNull!.candidates;
      expect(candidates.length, MockDiscoveryDataSource.profileCount);
      final scores = candidates.map((c) => c.compatibilityScore).toList();
      expect(scores.every((score) => score >= 61 && score <= 92), isTrue);
      expect(scores.toSet().length, greaterThan(5));
    });

    test('never returns self', () async {
      final repo = MockDiscoveryRepository(selfUid: 'mock-01');
      final result = await repo.getCandidates(radius: DiscoveryRadius.km50);
      final uids = result.valueOrNull!.candidates.map((c) => c.uid);
      expect(uids, isNot(contains('mock-01')));
    });

    test('like on a user who already likes you creates a demo match', () async {
      const uid = _FixedUid('user-1');
      final hub = DemoSocialHub(uidSource: uid);
      final repo = MockDiscoveryRepository(
        selfUid: 'user-1',
        demoHub: hub,
        currentUid: () => 'user-1',
      );
      final first = await repo.getCandidates(radius: DiscoveryRadius.km50);
      final elif = first.valueOrNull!.candidates.firstWhere(
        (candidate) => candidate.uid == 'mock-01',
      );
      final result = await repo.recordDecision(
        candidateUid: elif.uid,
        decision: DiscoveryDecision.like,
      );
      expect(result.valueOrNull?.matched, isTrue);
      expect(result.valueOrNull?.matchId, isNotNull);
      final matches = await hub.matches.watchMatches('user-1').first;
      expect(matches, isNotEmpty);
      expect(matches.first.otherUserId, 'mock-01');
    });

    test('pass never creates a match', () async {
      final repo = MockDiscoveryRepository();
      final first = await repo.getCandidates(radius: DiscoveryRadius.km50);
      final uid = first.valueOrNull!.candidates.first.uid;
      final result = await repo.recordDecision(
        candidateUid: uid,
        decision: DiscoveryDecision.pass,
      );
      expect(result.valueOrNull?.matched, isFalse);
    });

    test('restartDemo restores full stack', () async {
      final repo = MockDiscoveryRepository();
      final first = await repo.getCandidates(radius: DiscoveryRadius.km50);
      final uid = first.valueOrNull!.candidates.first.uid;
      await repo.recordDecision(
        candidateUid: uid,
        decision: DiscoveryDecision.pass,
      );
      final afterPass = await repo.getCandidates(radius: DiscoveryRadius.km50);
      expect(afterPass.valueOrNull!.candidates.length, 9);
      repo.restartDemo();
      final restored = await repo.getCandidates(radius: DiscoveryRadius.km50);
      expect(restored.valueOrNull!.candidates.length, 10);
    });
  });

  group('DiscoveryController actions', () {
    late MockDiscoveryRepository discovery;
    late DiscoveryController controller;

    setUp(() {
      discovery = MockDiscoveryRepository();
      controller = DiscoveryController(
        uid: 'self',
        locationRepository: FakeLocationRepository(
          permission: LocationPermissionStatus.denied,
        ),
        discoveryRepository: discovery,
      );
    });

    test('onLike removes candidate and prevents duplicate action', () async {
      await controller.skipLocation();
      final uid = controller.state.current!.uid;
      await controller.onLike(uid);
      expect(discovery.liked, contains(uid));
      expect(controller.state.candidates.where((c) => c.uid == uid), isEmpty);
      final before = controller.state.candidates.length;
      await controller.onLike(uid);
      expect(controller.state.candidates.length, before);
    });

    test('onPass records pass decision', () async {
      await controller.skipLocation();
      final uid = controller.state.current!.uid;
      await controller.onPass(uid);
      expect(discovery.passed, contains(uid));
    });

    test('onSuperLike records super like', () async {
      await controller.skipLocation();
      final uid = controller.state.current!.uid;
      await controller.onSuperLike(uid);
      expect(discovery.superLiked, contains(uid));
    });

    test('empty state after all mock profiles swiped', () async {
      await controller.skipLocation();
      await controller.setRadius(DiscoveryRadius.km50);
      while (controller.state.current != null) {
        await controller.onPass(controller.state.current!.uid);
      }
      expect(controller.state.hasSeenEveryone, isTrue);
      expect(controller.state.current, isNull);
    });

    test('restartDemo reloads candidates in mock mode', () async {
      await controller.skipLocation();
      await controller.setRadius(DiscoveryRadius.km50);
      while (controller.state.current != null) {
        await controller.onPass(controller.state.current!.uid);
      }
      await controller.restartDemo();
      expect(controller.state.hasSeenEveryone, isFalse);
      expect(controller.state.candidates.length, 10);
    });
  });
}
