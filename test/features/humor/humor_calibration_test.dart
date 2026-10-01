import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';

/// Records what the client sent and replays a canned Cloud Functions payload.
class _FakeBackend implements BackendCallable {
  _FakeBackend(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? payload,
  ]) async {
    calls.add(name);
    payloads.add(payload ?? const <String, dynamic>{});
    return responses[name] ?? const <String, dynamic>{};
  }
}

void main() {
  HumorController buildController(MockHumorDataSource source) {
    return HumorController(repository: HumorRepositoryImpl(dataSource: source));
  }

  List<String> idsOf(HumorController controller) =>
      controller.state.items.map((item) => item.contentId).toList();

  group('calibration contract', () {
    test('the client knows no item count of its own', () {
      const fresh = HumorCalibration.empty;
      expect(fresh.started, isFalse);
      expect(fresh.totalCount, 0);
      expect(fresh.remaining, 0);
      expect(fresh.continuesTomorrow, isFalse);
    });

    test('progress and remaining follow the total the server gave', () {
      const mid = HumorCalibration(completedCount: 9, totalCount: 15);
      expect(mid.started, isTrue);
      expect(mid.progress, closeTo(0.6, 0.0001));
      expect(mid.remaining, 6);

      // A retired item makes the calibration shorter; the client just shows it.
      const shorter = HumorCalibration(completedCount: 7, totalCount: 14);
      expect(shorter.progress, closeTo(0.5, 0.0001));
      expect(shorter.remaining, 7);

      const done = HumorCalibration(
        completedCount: 15,
        totalCount: 15,
        stage: HumorCalibrationStage.complete,
        complete: true,
      );
      expect(done.progress, 1);
      expect(done.remaining, 0);
    });

    test('unknown stage strings degrade to anchor rather than throwing', () {
      expect(
        HumorCalibration.parseStage('exploration'),
        HumorCalibrationStage.exploration,
      );
      expect(
        HumorCalibration.parseStage('something-new'),
        HumorCalibrationStage.anchor,
      );
      expect(HumorCalibration.parseStage(null), HumorCalibrationStage.anchor);
    });
  });

  group('functions data source parsing', () {
    test('feed carries the server calibration progress', () async {
      final backend = _FakeBackend({
        'getHumorFeed': {
          'items': [
            {
              'contentId': 'c7',
              'type': 'meme',
              'language': 'tr',
              'category': 'sarcasm',
              'humorTags': <String>['ironi'],
              'calibrationStage': null,
              'media': {'downloadUrl': 'https://example.test/a.png'},
            },
            {
              'contentId': 'c8',
              'type': 'image',
              'language': 'tr',
              'category': 'dry',
              'humorTags': <String>[],
              'media': {'downloadUrl': 'https://example.test/b.png'},
            },
          ],
          'nextCursor': null,
          'profileBuilding': true,
          'interactionCount': 6,
          'calibration': {
            'version': 1,
            'stage': 'adaptive',
            'completedCount': 6,
            'totalCount': 14,
            'complete': false,
            'insufficientPool': false,
            'continuesTomorrow': false,
          },
        },
      });
      final source = FunctionsHumorDataSource(backend: backend);

      final page = await source.getFeed();

      expect(page.calibration.completedCount, 6);
      expect(page.calibration.totalCount, 14);
      expect(page.calibration.complete, isFalse);
      expect(page.calibration.continuesTomorrow, isFalse);
      expect(page.items.map((item) => item.contentId), ['c7', 'c8']);
      expect(page.items.first.calibrationStage, isNull);
    });

    test('a paused calibration is reported as continuing tomorrow', () async {
      final backend = _FakeBackend({
        'getHumorFeed': {
          'items': <Object>[],
          'catalogExhausted': true,
          'profileBuilding': true,
          'interactionCount': 14,
          'calibration': {
            'completedCount': 14,
            'totalCount': 15,
            'complete': false,
            'continuesTomorrow': true,
          },
        },
      });
      final page = await FunctionsHumorDataSource(backend: backend).getFeed();

      expect(page.items, isEmpty);
      expect(page.calibration.continuesTomorrow, isTrue);
      expect(page.calibration.complete, isFalse);
    });

    test(
      'a backend without calibration data still yields a usable feed',
      () async {
        final backend = _FakeBackend({
          'getHumorFeed': {
            'items': [
              {
                'contentId': 'c1',
                'type': 'meme',
                'language': 'tr',
                'category': 'meme',
                'media': <String, dynamic>{},
              },
            ],
            'profileBuilding': true,
            'interactionCount': 2,
          },
        });
        final source = FunctionsHumorDataSource(backend: backend);

        final page = await source.getFeed();

        expect(page.items, hasLength(1));
        expect(page.items.first.calibrationStage, isNull);
        expect(page.calibration, HumorCalibration.empty);
      },
    );

    test('a missing or broken total is never replaced by a count kept '
        'on the client', () async {
      for (final total in <Object?>[null, 0, -3, 'fifteen']) {
        final backend = _FakeBackend({
          'getHumorFeed': {
            'items': <Object>[],
            'calibration': {'completedCount': 2, 'totalCount': total},
          },
        });
        final page = await FunctionsHumorDataSource(backend: backend).getFeed();
        expect(page.calibration.totalCount, 0, reason: 'totalCount: $total');
        expect(page.calibration.completedCount, 2);
      }
    });

    test('the feed request carries nothing that selects content', () async {
      final backend = _FakeBackend({'getHumorFeed': const {}});
      await FunctionsHumorDataSource(backend: backend).getFeed();

      for (final key in backend.payloads.single.keys) {
        expect(
          ['languages', 'limit', 'cursor'],
          contains(key),
          reason: 'unexpected request field: $key',
        );
      }
    });

    test('a completed calibration clears profileBuilding', () async {
      final backend = _FakeBackend({
        'getHumorProfile': {
          'confidence': 0.42,
          'interactionCount': 21,
          'profileBuilding': true, // stale field from an older payload shape
          'topVibes': [
            {'dim': 'sarcasm', 'value': 88},
          ],
          'version': 1,
          'calibration': {
            'version': 1,
            'stage': 'complete',
            'completedCount': 15,
            'totalCount': 15,
            'complete': true,
          },
        },
      });
      final source = FunctionsHumorDataSource(backend: backend);

      final profile = await source.getProfile();

      expect(profile.calibrationComplete, isTrue);
      expect(
        profile.profileBuilding,
        isFalse,
        reason: 'calibration state is authoritative over the legacy flag',
      );
      // Lifetime learning keeps its own counter.
      expect(profile.interactionCount, 21);
    });

    test('a profile is building exactly while the server says so', () async {
      Future<bool> buildingFor(Map<String, dynamic> payload) async {
        final backend = _FakeBackend({'getHumorProfile': payload});
        return (await FunctionsHumorDataSource(
          backend: backend,
        ).getProfile()).profileBuilding;
      }

      // No count of ratings decides it on the client.
      expect(
        await buildingFor({
          'interactionCount': 40,
          'profileBuilding': true,
          'calibration': {'completedCount': 0, 'totalCount': 15},
        }),
        isTrue,
      );
      expect(
        await buildingFor({
          'interactionCount': 3,
          'profileBuilding': false,
          'calibration': {'completedCount': 0, 'totalCount': 15},
        }),
        isFalse,
      );
    });

    test('feedback returns the post-rating calibration state', () async {
      final backend = _FakeBackend({
        'submitHumorFeedback': {
          'ok': true,
          'profileBuilding': false,
          'interactionCount': 15,
          'confidence': 0.31,
          'calibration': {
            'version': 1,
            'stage': 'complete',
            'completedCount': 15,
            'totalCount': 15,
            'complete': true,
          },
        },
      });
      final source = FunctionsHumorDataSource(backend: backend);

      final result = await source.submitFeedback(
        contentId: 'c15',
        rating: HumorRating.veryFunny,
      );

      expect(result.calibration.complete, isTrue);
      expect(result.calibration.stage, HumorCalibrationStage.complete);
      // The client echoes the item it was shown and its rating — nothing
      // about where it believes it is in the sequence, and no day.
      final payload = backend.payloads.single;
      expect(payload.keys.toSet(), {
        'contentId',
        'rating',
        'dwellMs',
        'replayCount',
      });
      expect(firestoreInt(payload['dwellMs'], -1), 0);
    });

    test('a media skip sends no rating', () async {
      final backend = _FakeBackend({
        'submitHumorFeedback': {
          'ok': true,
          'profileBuilding': true,
          'interactionCount': 3,
          'confidence': 0.07,
          'calibration': {
            'version': 1,
            'stage': 'anchor',
            'completedCount': 3,
            'totalCount': 15,
            'complete': false,
          },
        },
      });
      final source = FunctionsHumorDataSource(backend: backend);

      final result = await source.skipContent(
        contentId: 'c4',
        skipReason: HumorSkipReason.mediaFailed,
      );

      expect(backend.calls, ['submitHumorFeedback']);
      expect(backend.payloads.single, {
        'contentId': 'c4',
        'skipped': true,
        'skipReason': 'media_failed',
      });
      expect(result.calibration.completedCount, 3);
      expect(result.interactionCount, 3);
    });
  });

  group('controller', () {
    test('mirrors server calibration instead of computing its own', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);

      expect(controller.state.calibration.totalCount, 0);
      await controller.load();
      expect(controller.state.calibration.completedCount, 0);
      expect(
        controller.state.calibration.totalCount,
        MockHumorDataSource.onboardingCount,
      );
      expect(controller.state.isCalibrating, isTrue);

      await controller.rate(HumorRating.veryFunny);
      expect(controller.state.calibration.completedCount, 1);
    });

    test('shows the canonical items in the canonical order', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);
      await controller.load();

      expect(
        idsOf(controller),
        source.sequenceIds.take(MockHumorDataSource.onboardingCount),
      );
      expect(idsOf(controller).toSet().length, idsOf(controller).length);
    });

    test('every member gets the same items in the same order', () async {
      final first = buildController(MockHumorDataSource());
      final second = buildController(MockHumorDataSource());
      await first.load();
      await second.load();

      expect(idsOf(first), idsOf(second));
    });

    test('completes on the last item, and not before', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);
      await controller.load();
      final total = controller.state.calibration.totalCount;

      for (var i = 0; i < total - 1; i += 1) {
        await controller.rate(HumorRating.funny);
        expect(controller.state.calibration.complete, isFalse);
        expect(controller.state.calibration.completedCount, i + 1);
      }
      await controller.rate(HumorRating.funny);

      expect(controller.state.calibration.complete, isTrue);
      expect(controller.state.isCalibrating, isFalse);
      expect(controller.state.calibration.completedCount, total);
      expect(controller.state.calibrationJustCompleted, isTrue);
    });

    test('resumes at the item it stopped on', () async {
      final source = MockHumorDataSource();
      final first = buildController(source);
      await first.load();
      for (var i = 0; i < 7; i += 1) {
        await first.rate(HumorRating.funny);
      }

      // A restart, or a second device: only the server knows the position.
      final resumed = buildController(source);
      await resumed.load();

      expect(resumed.state.calibration.completedCount, 7);
      expect(resumed.state.current?.contentId, source.sequenceIds[7]);
      expect(idsOf(resumed), source.sequenceIds.sublist(7, 15));
    });

    test(
      'finishing the calibration opens no further content that day',
      () async {
        final source = MockHumorDataSource();
        final controller = buildController(source);
        await controller.load();
        final total = controller.state.calibration.totalCount;
        for (var i = 0; i < total; i += 1) {
          await controller.rate(HumorRating.funny);
        }
        final atCompletion = controller.state.profile.interactionCount;

        await controller.loadMore();

        expect(controller.state.current, isNull);
        expect(controller.state.reachedEnd, isTrue);
        expect(controller.state.catalogExhausted, isTrue);
        // The next item of the sequence is tomorrow's: the server refuses it.
        final result = await HumorRepositoryImpl(dataSource: source)
            .submitFeedback(
              contentId: source.sequenceIds[total],
              rating: HumorRating.veryFunny,
            );
        expect(result.isError, isTrue);
        expect(source.profile.interactionCount, atCompletion);
      },
    );

    test('an item whose media failed pauses the calibration until '
        'tomorrow, and the pause survives a rating response and a profile '
        'refresh', () async {
      // The pause is observed only by the feed. Neither the feedback
      // response nor the profile response carries it, so every merge that
      // takes calibration from those payloads must preserve the flag.
      final source = MockHumorDataSource(
        seed: MockHumorDataSource.seedCatalog.take(3).toList(),
      );
      final controller = buildController(source);
      await controller.load();
      final failed = controller.state.current!.contentId;

      await controller.skipUnplayable(failed);
      await controller.rate(HumorRating.funny);
      await controller.rate(HumorRating.funny);

      expect(controller.state.continuesTomorrow, isTrue);
      expect(controller.state.calibration.complete, isFalse);
      expect(controller.state.calibration.completedCount, 2);
      expect(controller.state.reachedEnd, isTrue);
      expect(source.ratingOf(failed), isNull);

      await controller.refreshProfile();
      expect(controller.state.continuesTomorrow, isTrue);

      // The next day brings back exactly the item that failed.
      source.closeDay('2099-01-02');
      await controller.load();
      expect(idsOf(controller), [failed]);
      expect(controller.state.continuesTomorrow, isFalse);
      await controller.rate(HumorRating.funny);
      expect(controller.state.calibration.complete, isTrue);
    });

    test('an empty catalogue is reported, not shown as a finished '
        'calibration', () async {
      final controller = buildController(MockHumorDataSource(seed: const []));

      await controller.load();

      expect(controller.state.items, isEmpty);
      expect(controller.state.catalogEmpty, isTrue);
      expect(controller.state.calibration.insufficientPool, isTrue);
      expect(controller.state.calibration.complete, isFalse);
    });
  });
}
