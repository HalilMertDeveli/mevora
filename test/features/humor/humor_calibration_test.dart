import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
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

  group('calibration contract', () {
    test('stage totals match the 6 / 6 / 3 product contract', () {
      expect(HumorCalibration.anchorInteractions, 6);
      expect(HumorCalibration.adaptiveInteractions, 6);
      expect(HumorCalibration.explorationInteractions, 3);
      expect(HumorCalibration.totalInteractions, 15);
    });

    test('progress and remaining stay inside the contract', () {
      const fresh = HumorCalibration.empty;
      expect(fresh.started, isFalse);
      expect(fresh.progress, 0);
      expect(fresh.remaining, 15);

      const mid = HumorCalibration(completedCount: 9, stage: HumorCalibrationStage.adaptive);
      expect(mid.started, isTrue);
      expect(mid.progress, closeTo(0.6, 0.0001));
      expect(mid.remaining, 6);

      const done = HumorCalibration(
        completedCount: 15,
        stage: HumorCalibrationStage.complete,
        complete: true,
      );
      expect(done.progress, 1);
      expect(done.remaining, 0);
    });

    test('unknown stage strings degrade to anchor rather than throwing', () {
      expect(HumorCalibration.parseStage('exploration'),
          HumorCalibrationStage.exploration);
      expect(HumorCalibration.parseStage('something-new'),
          HumorCalibrationStage.anchor);
      expect(HumorCalibration.parseStage(null), HumorCalibrationStage.anchor);
    });
  });

  group('functions data source parsing', () {
    test('feed carries calibration progress and per-item stage', () async {
      final backend = _FakeBackend({
        'getHumorFeed': {
          'items': [
            {
              'contentId': 'c1',
              'type': 'meme',
              'language': 'tr',
              'category': 'sarcasm',
              'humorTags': <String>['ironi'],
              'calibrationStage': 'anchor',
              'media': {'downloadUrl': 'https://example.test/a.png'},
            },
            {
              'contentId': 'c2',
              'type': 'image',
              'language': 'tr',
              'category': 'dry',
              'humorTags': <String>[],
              'calibrationStage': 'adaptive',
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
            'totalCount': 15,
            'complete': false,
            'insufficientPool': false,
          },
        },
      });
      final source = FunctionsHumorDataSource(backend: backend);

      final page = await source.getFeed(languages: const ['tr']);

      expect(page.calibration.stage, HumorCalibrationStage.adaptive);
      expect(page.calibration.completedCount, 6);
      expect(page.calibration.totalCount, 15);
      expect(page.calibration.complete, isFalse);
      expect(page.items.first.calibrationStage, HumorCalibrationStage.anchor);
      expect(page.items.first.isCalibrationItem, isTrue);
      expect(page.items[1].calibrationStage, HumorCalibrationStage.adaptive);
    });

    test('a backend without calibration data still yields a usable feed', () async {
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
      // The client must not send anything calibration-related upward.
      final payload = backend.payloads.single;
      expect(payload.containsKey('calibration'), isFalse);
      expect(payload.containsKey('stage'), isFalse);
      expect(payload.containsKey('completedCount'), isFalse);
      expect(firestoreInt(payload['dwellMs'], -1), 0);
    });
  });

  group('controller', () {
    test('mirrors server calibration instead of computing its own', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);

      await controller.load();
      expect(controller.state.calibration.completedCount, 0);
      expect(controller.state.calibration.stage, HumorCalibrationStage.anchor);
      expect(controller.state.isCalibrating, isTrue);
      expect(controller.state.currentStage, HumorCalibrationStage.anchor);

      await controller.rate(HumorRating.veryFunny);
      expect(controller.state.calibration.completedCount, 1);
      expect(controller.state.calibration.stage, HumorCalibrationStage.anchor);
    });

    test('walks anchor → adaptive → exploration → complete', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);
      await controller.load();

      final seenStages = <int, HumorCalibrationStage>{};
      for (var i = 0; i < HumorCalibration.totalInteractions; i += 1) {
        seenStages[i] = controller.state.calibration.stage;
        await controller.rate(HumorRating.funny);
      }

      expect(seenStages[0], HumorCalibrationStage.anchor);
      expect(seenStages[5], HumorCalibrationStage.anchor);
      expect(seenStages[6], HumorCalibrationStage.adaptive);
      expect(seenStages[11], HumorCalibrationStage.adaptive);
      expect(seenStages[12], HumorCalibrationStage.exploration);
      expect(seenStages[14], HumorCalibrationStage.exploration);

      expect(controller.state.calibration.complete, isTrue);
      expect(controller.state.calibration.stage, HumorCalibrationStage.complete);
      expect(controller.state.isCalibrating, isFalse);
      expect(controller.state.calibration.completedCount, 15);
    });

    test('profile keeps learning after calibration completes', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);
      await controller.load();

      for (var i = 0; i < HumorCalibration.totalInteractions; i += 1) {
        await controller.rate(HumorRating.funny);
      }
      final atCompletion = controller.state.profile;
      expect(controller.state.calibration.complete, isTrue);

      await controller.rate(HumorRating.veryFunny);

      expect(
        controller.state.profile.interactionCount,
        atCompletion.interactionCount + 1,
        reason: 'interaction 16 must still count',
      );
      expect(
        controller.state.profile.confidence,
        greaterThan(atCompletion.confidence),
        reason: 'confidence must keep growing past the calibration milestone',
      );
      expect(controller.state.profile.profileBuilding, isFalse);
      // The milestone itself stays frozen at 15.
      expect(controller.state.calibration.completedCount, 15);
    });

    test('calibration items are never duplicated across a page', () async {
      final source = MockHumorDataSource();
      final controller = buildController(source);
      await controller.load();

      final ids = controller.state.items.map((item) => item.contentId).toList();
      expect(ids.toSet().length, ids.length);
      for (final item in controller.state.items) {
        expect(item.isCalibrationItem, isTrue);
      }
    });

    test('a short curated pool is reported, not silently padded', () async {
      // Only four items available for a fifteen-item calibration.
      final source = MockHumorDataSource(
        seed: MockHumorDataSource.seedCatalog.take(4).toList(),
      );
      final controller = buildController(source);

      await controller.load();

      expect(controller.state.items, hasLength(4));
      expect(controller.state.calibration.insufficientPool, isTrue);
      expect(controller.state.calibration.complete, isFalse);
    });
  });
}
