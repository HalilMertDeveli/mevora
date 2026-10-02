import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/matching/data/firebase/firebase_social_data.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/data/overlay/overlay_social_repositories.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

import '../../helpers/fake_match_firestore.dart';

const _matchId = 'user-1_user-2';
const _wait = Duration(seconds: 1);

class _NoBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async => const {};
}

/// A remote whose match listen fails the way a refused Firestore listen does.
class _DeniedRemote implements MatchRepository {
  @override
  Stream<Match?> watchMatch(String matchId) {
    final controller = StreamController<Match?>();
    controller.addError(matchReadDenied());
    return controller.stream;
  }

  @override
  Stream<List<MatchListItem>> watchMatches(String uid, {int? limit}) =>
      const Stream.empty();

  @override
  Future<Match?> getMatch(String matchId) async => null;

  @override
  Future<void> markOpened(String matchId, String uid) async {}
}

void main() {
  group('FirebaseMatchRepository.watchMatch', () {
    late FakeMatchFirestore firestore;
    late FirebaseMatchRepository repository;

    setUp(() {
      firestore = FakeMatchFirestore();
      addTearDown(firestore.dispose);
      repository = FirebaseMatchRepository(
        callable: _NoBackend(),
        uidSource: MutableAuthUidSource('user-1'),
        firestore: firestore,
      );
    });

    test('a refused listen is reported as no match, not as silence', () async {
      firestore.deny(FirestorePaths.match(_matchId));

      final first = await repository.watchMatch(_matchId).first.timeout(_wait);

      expect(first, isNull);
    });

    test('a refused listen does not surface as a stream error', () async {
      final errors = <Object>[];
      final events = <Match?>[];
      final subscription = repository
          .watchMatch(_matchId)
          .listen(events.add, onError: errors.add);
      addTearDown(subscription.cancel);

      firestore.deny(FirestorePaths.match(_matchId));
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(events, [null]);
    });

    test('a match that becomes unreadable ends as no match', () async {
      final events = <Match?>[];
      final subscription = repository.watchMatch(_matchId).listen(events.add);
      addTearDown(subscription.cancel);

      firestore.emit(FirestorePaths.match(_matchId), {
        'userIds': ['user-1', 'user-2'],
        'isActive': true,
      });
      await pumpEventQueue();
      firestore.deny(FirestorePaths.match(_matchId));
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.first?.isActive, isTrue);
      expect(events.last, isNull);
    });

    test('a missing match the viewer may read is still no match', () async {
      firestore.emit(FirestorePaths.match(_matchId), null);

      final first = await repository.watchMatch(_matchId).first.timeout(_wait);

      expect(first, isNull);
    });
  });

  group('OverlayMatchRepository.watchMatch', () {
    test('a remote failure is reported as no match, not as silence', () async {
      final repository = OverlayMatchRepository(
        remote: _DeniedRemote(),
        hub: DemoSocialHub(uidSource: MutableAuthUidSource('user-1')),
      );

      final first = await repository.watchMatch(_matchId).first.timeout(_wait);

      expect(first, isNull);
    });
  });
}
