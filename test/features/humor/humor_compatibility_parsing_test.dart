import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';

class _FakeBackend implements BackendCallable {
  _FakeBackend(this.response);

  final Map<String, dynamic> response;
  final calls = <String, Map<String, dynamic>?>{};

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls[name] = data;
    return response;
  }
}

void main() {
  group('getMatchCompatibility parsing (contract C5)', () {
    test(
      'keeps only known shared categories and ignores legacy fields',
      () async {
        final backend = _FakeBackend({
          'available': true,
          'score': 74,
          'strongestShared': [
            'sarcasm',
            'not-a-category',
            7,
            'dark',
            'sarcasm',
          ],
          'reason': null,
          // An older backend still sent these; they must go nowhere.
          'differences': [
            {'dim': 'dark', 'a': 80, 'b': 12},
          ],
          'confidence': 0.31,
        });
        final source = FunctionsHumorDataSource(backend: backend);

        final result = await source.getMatchCompatibility('m_1');

        expect(backend.calls['getMatchHumorCompatibility'], {'matchId': 'm_1'});
        expect(result.available, isTrue);
        expect(result.hasResult, isTrue);
        expect(result.score, 74);
        expect(result.strongestShared, [
          HumorCategory.sarcasm,
          HumorCategory.dark,
        ]);
        expect(result.reason, isNull);
        expect(result.level, HumorCompatibilityLevel.high);
      },
    );

    test('building payload is unavailable with its reason', () async {
      final source = FunctionsHumorDataSource(
        backend: _FakeBackend({
          'available': false,
          'score': null,
          'strongestShared': <String>[],
          'reason': 'building',
        }),
      );

      final result = await source.getMatchCompatibility('m_1');

      expect(result.available, isFalse);
      expect(result.hasResult, isFalse);
      expect(result.isBuilding, isTrue);
      expect(result.level, isNull);
    });

    test('available without a score is treated as unavailable', () async {
      final source = FunctionsHumorDataSource(
        backend: _FakeBackend({'available': true, 'score': null}),
      );

      final result = await source.getMatchCompatibility('m_1');

      expect(result.available, isFalse);
      expect(result.hasResult, isFalse);
    });

    test(
      'score is clamped to 0..100 and a non-string reason is dropped',
      () async {
        final source = FunctionsHumorDataSource(
          backend: _FakeBackend({
            'available': true,
            'score': 140.6,
            'strongestShared': 'sarcasm',
            'reason': 3,
          }),
        );

        final result = await source.getMatchCompatibility('m_1');

        expect(result.score, 100);
        expect(result.strongestShared, isEmpty);
        expect(result.reason, isNull);
      },
    );
  });

  group('HumorCompatibility levels', () {
    test('bucket the score coarsely', () {
      expect(HumorCompatibility.levelOf(100), HumorCompatibilityLevel.high);
      expect(HumorCompatibility.levelOf(70), HumorCompatibilityLevel.high);
      expect(HumorCompatibility.levelOf(69), HumorCompatibilityLevel.medium);
      expect(HumorCompatibility.levelOf(50), HumorCompatibilityLevel.medium);
      expect(HumorCompatibility.levelOf(49), HumorCompatibilityLevel.low);
      expect(HumorCompatibility.levelOf(0), HumorCompatibilityLevel.low);
    });
  });

  group('MockHumorDataSource.getMatchCompatibility', () {
    test('reports building while this side is unfinished', () async {
      final source = MockHumorDataSource();

      final result = await source.getMatchCompatibility('m_1');

      expect(result.isBuilding, isTrue);
      expect(result.hasResult, isFalse);
    });

    test('never invents a peer reading once this side is done', () async {
      final source = MockHumorDataSource()..completeCalibration();
      expect(source.calibration.complete, isTrue);

      final result = await source.getMatchCompatibility('m_1');

      expect(result.hasResult, isFalse);
      expect(result.isBuilding, isFalse);
    });
  });
}
