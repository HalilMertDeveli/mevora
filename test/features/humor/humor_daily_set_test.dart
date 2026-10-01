import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/pages/humor_daily_page.dart';

Map<String, dynamic> _item(int i) => {
  'contentId': 'c$i',
  'type': 'video',
  'language': 'tr',
  'category': 'absurd',
  'humorTags': ['a'],
  'media': {
    'downloadUrl': 'https://example.com/$i.mp4',
    'thumbUrl': 'https://example.com/$i.jpg',
    'aspectRatio': 0.5625,
    'durationMs': 8000,
    'textBody': null,
  },
  'attribution': null,
  'calibrationStage': null,
};

/// Items in a day, as the server serves them.
const _daySize = 5;

Map<String, dynamic> _ready({int answered = 2, bool completed = false}) => {
  'status': 'ready',
  'lockedReason': null,
  'dayId': '2026-09-29',
  'setVersion': 1,
  'total': _daySize,
  'answeredCount': answered,
  'completed': completed,
  'nextIndex': completed ? _daySize : answered,
  'items': [for (var i = 0; i < _daySize; i += 1) _item(i)],
  'answers': [
    for (var i = 0; i < answered; i += 1)
      {'index': i, 'contentId': 'c$i', 'rating': 'funny', 'skipped': false},
  ],
};

/// Records every call and answers (or fails) as scripted.
class _Backend implements BackendCallable {
  _Backend({this.response = const {}, this.errorCode, this.errorMessage});

  final Map<String, dynamic> response;
  final String? errorCode;
  final String? errorMessage;
  final List<(String, Map<String, dynamic>?)> calls = [];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add((name, data));
    final code = errorCode;
    if (code != null) {
      throw FirebaseFunctionsException(code: code, message: errorMessage ?? '');
    }
    return response;
  }
}

void main() {
  group('HumorDailySet.fromMap', () {
    test('parses a ready set with items in server order', () {
      final set = HumorDailySet.fromMap(_ready());

      expect(set.status, HumorDailyStatus.ready);
      expect(set.isReady, isTrue);
      expect(set.dayId, '2026-09-29');
      expect(set.setVersion, 1);
      expect(set.total, _daySize);
      expect(set.answeredCount, 2);
      expect(set.completed, isFalse);
      expect(set.nextIndex, 2);
      expect(set.items.map((i) => i.contentId), [
        for (var i = 0; i < _daySize; i += 1) 'c$i',
      ]);
      expect(set.items.first.type, HumorContentType.video);
      expect(set.items.first.category, HumorCategory.absurd);
      expect(set.items.first.aspectRatio, closeTo(0.5625, 1e-9));
      expect(set.answers, hasLength(2));
      expect(set.answers.first.rating, HumorRating.funny);
      expect(set.showsEntryCard, isTrue);
      expect(set.inProgress, isTrue);
    });

    test('a completed set points past the end', () {
      final set = HumorDailySet.fromMap(
        _ready(answered: _daySize, completed: true),
      );
      expect(set.completed, isTrue);
      expect(set.nextIndex, _daySize);
      expect(set.showsEntryCard, isTrue);
    });

    test('locked carries its reason and nothing to play', () {
      final calibrating = HumorDailySet.fromMap({
        'status': 'locked',
        'lockedReason': 'calibration_incomplete',
        'dayId': '2026-09-29',
        'items': [_item(0)],
      });
      expect(calibrating.isLocked, isTrue);
      expect(
        calibrating.lockedReason,
        HumorDailyLockedReason.calibrationIncomplete,
      );
      expect(calibrating.items, isEmpty);
      expect(calibrating.showsEntryCard, isFalse);
      expect(calibrating.startsTomorrow, isFalse);

      final tomorrow = HumorDailySet.fromMap({
        'status': 'locked',
        'lockedReason': 'starts_tomorrow',
      });
      expect(tomorrow.startsTomorrow, isTrue);
      expect(tomorrow.showsEntryCard, isFalse);

      final finished = HumorDailySet.fromMap({
        'status': 'locked',
        'lockedReason': 'sequence_complete',
      });
      expect(finished.sequenceComplete, isTrue);
      expect(finished.startsTomorrow, isFalse);
      expect(finished.showsEntryCard, isFalse);

      final unknown = HumorDailySet.fromMap({'status': 'locked'});
      expect(unknown.lockedReason, HumorDailyLockedReason.unknown);
      expect(unknown.sequenceComplete, isFalse);
    });

    test('takes the size of the day from the server, whatever it is', () {
      for (final size in [1, 3, 5, 7]) {
        final set = HumorDailySet.fromMap({
          'status': 'ready',
          'dayId': '2026-09-29',
          'total': size,
          'answeredCount': 0,
          'nextIndex': 0,
          'items': [for (var i = 0; i < size; i += 1) _item(i)],
        });
        expect(set.total, size);
        expect(set.items, hasLength(size));
      }
    });

    test('not_ready is calm and empty', () {
      final set = HumorDailySet.fromMap({
        'status': 'not_ready',
        'dayId': '2026-09-29',
        'items': const <Object>[],
      });
      expect(set.isNotReady, isTrue);
      expect(set.showsEntryCard, isFalse);
      expect(set.items, isEmpty);
    });

    test('an unknown status or an empty payload is treated as not_ready', () {
      expect(
        HumorDailySet.fromMap({'status': 'paused'}).status,
        HumorDailyStatus.notReady,
      );
      expect(HumorDailySet.fromMap(const {}).status, HumorDailyStatus.notReady);
    });

    test('a "ready" set with nothing to play is never shown as ready', () {
      final set = HumorDailySet.fromMap({
        ..._ready(),
        'items': const <Object>[],
      });
      expect(set.status, HumorDailyStatus.notReady);
    });

    test('malformed fields fall back to safe values', () {
      final set = HumorDailySet.fromMap({
        'status': 'ready',
        'dayId': '2026-09-29',
        'total': '5',
        'answeredCount': 99,
        'nextIndex': -3,
        'items': [
          for (var i = 0; i < _daySize; i += 1) _item(i),
          'junk',
          {'contentId': ''},
        ],
        'answers': ['junk', null],
      });
      expect(set.total, _daySize);
      expect(set.answeredCount, _daySize, reason: 'clamped to total');
      expect(set.completed, isTrue);
      expect(set.nextIndex, _daySize);
      expect(set.items, hasLength(_daySize));
      expect(set.answers, isEmpty);
    });
  });

  test('HumorDailyProgress.fromMap reads the submit response', () {
    final progress = HumorDailyProgress.fromMap({
      'ok': true,
      'dayId': '2026-09-29',
      'setVersion': 2,
      'total': _daySize,
      'answeredCount': 3,
      'completed': false,
      'nextIndex': 3,
      'alreadyAnswered': true,
    });
    expect(progress.dayId, '2026-09-29');
    expect(progress.setVersion, 2);
    expect(progress.total, _daySize);
    expect(progress.answeredCount, 3);
    expect(progress.nextIndex, 3);
    expect(progress.completed, isFalse);
    expect(progress.alreadyAnswered, isTrue);
  });

  test('CTA: Başla, then Devam et, then Bugünlük tamam', () {
    expect(
      HumorDailyCta.of(HumorDailySet.fromMap(_ready(answered: 0))),
      HumorDailyCta.start,
    );
    expect(
      HumorDailyCta.of(HumorDailySet.fromMap(_ready(answered: 2))),
      HumorDailyCta.resume,
    );
    expect(
      HumorDailyCta.of(
        HumorDailySet.fromMap(_ready(answered: _daySize, completed: true)),
      ),
      HumorDailyCta.done,
    );
  });

  test('microcopy follows the position through a five-item day', () {
    expect(HumorDailyHint.of(1, _daySize), HumorDailyHint.start);
    expect(HumorDailyHint.of(2, _daySize), HumorDailyHint.middle);
    expect(HumorDailyHint.of(3, _daySize), HumorDailyHint.middle);
    expect(HumorDailyHint.of(4, _daySize), HumorDailyHint.middle);
    expect(HumorDailyHint.of(5, _daySize), HumorDailyHint.end);
  });

  test('microcopy scales with whatever size the server sends', () {
    // A shorter day (an item was retired or taken down).
    expect(HumorDailyHint.of(1, 4), HumorDailyHint.start);
    expect(HumorDailyHint.of(2, 4), HumorDailyHint.middle);
    expect(HumorDailyHint.of(4, 4), HumorDailyHint.end);
    expect(HumorDailyHint.of(1, 3), HumorDailyHint.start);
    expect(HumorDailyHint.of(2, 3), HumorDailyHint.middle);
    expect(HumorDailyHint.of(3, 3), HumorDailyHint.end);
    expect(HumorDailyHint.of(1, 1), HumorDailyHint.start);
    // A longer one: a third at each end, never more than three items.
    expect(HumorDailyHint.of(3, 12), HumorDailyHint.start);
    expect(HumorDailyHint.of(4, 12), HumorDailyHint.middle);
    expect(HumorDailyHint.of(9, 12), HumorDailyHint.middle);
    expect(HumorDailyHint.of(10, 12), HumorDailyHint.end);
  });

  group('Functions data source and repository', () {
    test('getDailyHumorSet is called with an empty request', () async {
      final backend = _Backend(response: _ready());
      final repository = HumorRepositoryImpl(
        dataSource: FunctionsHumorDataSource(backend: backend),
      );

      final result = await repository.getDailySet();

      expect(result.valueOrNull?.total, _daySize);
      expect(backend.calls.single.$1, 'getDailyHumorSet');
      expect(backend.calls.single.$2, isEmpty);
    });

    test('a rating sends dayId, contentId and rating', () async {
      final backend = _Backend(
        response: {
          'ok': true,
          'dayId': '2026-09-29',
          'setVersion': 1,
          'total': _daySize,
          'answeredCount': 4,
          'completed': false,
          'nextIndex': 4,
          'alreadyAnswered': false,
        },
      );
      final repository = HumorRepositoryImpl(
        dataSource: FunctionsHumorDataSource(backend: backend),
      );

      final result = await repository.submitDailyResponse(
        dayId: '2026-09-29',
        contentId: 'c4',
        rating: HumorRating.veryFunny,
        dwellMs: 1200,
      );

      final outcome = result.valueOrNull;
      expect(outcome, isA<HumorDailyAccepted>());
      expect((outcome! as HumorDailyAccepted).progress.nextIndex, 4);
      final (name, payload) = backend.calls.single;
      expect(name, 'submitDailyHumorResponse');
      // The day and the item echo what the server handed out. Nothing names a
      // position, a start index or the items the client would like next.
      expect(payload, {
        'dayId': '2026-09-29',
        'contentId': 'c4',
        'rating': 'very_funny',
        'dwellMs': 1200,
        'replayCount': 0,
      });
    });

    test('a media failure is the only skip and carries its reason', () async {
      final backend = _Backend(
        response: {
          'ok': true,
          'dayId': 'd',
          'total': _daySize,
          'answeredCount': 1,
        },
      );
      final repository = HumorRepositoryImpl(
        dataSource: FunctionsHumorDataSource(backend: backend),
      );

      await repository.skipDailyItem(dayId: 'd', contentId: 'c0');

      final payload = backend.calls.single.$2!;
      expect(payload['skipped'], isTrue);
      expect(payload['skipReason'], 'media_failed');
      expect(payload.containsKey('rating'), isFalse);
    });

    test('state refusals become a reload, not a failure', () async {
      final cases = <(String, String), HumorDailyStaleReason>{
        ('failed-precondition', 'day-closed'): HumorDailyStaleReason.dayClosed,
        ('failed-precondition', 'slot-replaced'):
            HumorDailyStaleReason.slotReplaced,
        ('failed-precondition', 'not-eligible'):
            HumorDailyStaleReason.notEligible,
        ('not-found', 'content-unavailable'):
            HumorDailyStaleReason.contentUnavailable,
      };
      for (final entry in cases.entries) {
        final repository = HumorRepositoryImpl(
          dataSource: FunctionsHumorDataSource(
            backend: _Backend(
              errorCode: entry.key.$1,
              errorMessage: entry.key.$2,
            ),
          ),
        );
        final result = await repository.submitDailyResponse(
          dayId: 'd',
          contentId: 'c0',
          rating: HumorRating.funny,
        );
        final outcome = result.valueOrNull;
        expect(outcome, isA<HumorDailyStale>(), reason: '${entry.key}');
        expect((outcome! as HumorDailyStale).reason, entry.value);
      }
    });

    test('a network failure stays a failure', () async {
      final repository = HumorRepositoryImpl(
        dataSource: FunctionsHumorDataSource(
          backend: _Backend(errorCode: 'unavailable'),
        ),
      );
      final result = await repository.skipDailyItem(
        dayId: 'd',
        contentId: 'c0',
      );
      expect(result.failureOrNull, isA<NetworkFailure>());
    });
  });

  group('mock daily day', () {
    MockHumorDataSource calibrated() =>
        MockHumorDataSource()..completeCalibration();

    test('is locked until calibration is complete', () async {
      final set = await MockHumorDataSource().getDailySet();
      expect(set.lockedReason, HumorDailyLockedReason.calibrationIncomplete);
    });

    test('starts the day after the calibration is finished, never the '
        'same day', () async {
      final source = MockHumorDataSource();
      for (final contentId in source.sequenceIds.take(
        MockHumorDataSource.onboardingCount,
      )) {
        await source.submitFeedback(
          contentId: contentId,
          rating: HumorRating.funny,
        );
      }
      expect(source.calibration.complete, isTrue);

      final sameDay = await source.getDailySet();
      expect(sameDay.startsTomorrow, isTrue);
      expect(sameDay.items, isEmpty);

      source.closeDay('2099-01-02');
      final nextDay = await source.getDailySet();
      expect(nextDay.isReady, isTrue);
      expect(nextDay.total, _daySize);
    });

    test('serves five items; the same answer again is idempotent and a '
        'changed rating replaces it', () async {
      final source = calibrated();
      final set = await source.getDailySet();
      expect(set.isReady, isTrue);
      expect(set.total, _daySize);
      expect(set.items, hasLength(_daySize));
      expect(MockHumorDataSource.dailySetSize, _daySize);
      final before = source.profile.interactionCount;

      final first = await source.submitDailyResponse(
        dayId: set.dayId,
        contentId: set.items.first.contentId,
        rating: HumorRating.funny,
      );
      final again = await source.submitDailyResponse(
        dayId: set.dayId,
        contentId: set.items.first.contentId,
        rating: HumorRating.funny,
      );
      expect(first.answeredCount, 1);
      expect(first.alreadyAnswered, isFalse);
      expect(again.answeredCount, 1);
      expect(again.nextIndex, 1);
      expect(again.alreadyAnswered, isTrue);
      expect(source.profile.interactionCount, before + 1);

      final changed = await source.submitDailyResponse(
        dayId: set.dayId,
        contentId: set.items.first.contentId,
        rating: HumorRating.notFunny,
      );
      expect(changed.answeredCount, 1);
      expect(source.dailyAnswers[0]!.rating, HumorRating.notFunny);
      expect(
        source.profile.interactionCount,
        before + 1,
        reason: 'a changed rating replaces, it is not a second rating',
      );
    });

    test('refuses the old day once it has closed', () async {
      final source = calibrated();
      final set = await source.getDailySet();
      source.closeDay('2099-01-01');
      await expectLater(
        source.submitDailyResponse(
          dayId: set.dayId,
          contentId: set.items.first.contentId,
          rating: HumorRating.funny,
        ),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (e) => e.message,
            'message',
            'day-closed',
          ),
        ),
      );
    });

    test('refuses an item that is not one of today\'s', () async {
      final source = calibrated();
      final set = await source.getDailySet();
      final tomorrow =
          source.sequenceIds[MockHumorDataSource.onboardingCount + _daySize];
      await expectLater(
        source.submitDailyResponse(
          dayId: set.dayId,
          contentId: tomorrow,
          rating: HumorRating.funny,
        ),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (e) => e.message,
            'message',
            'slot-replaced',
          ),
        ),
      );
    });
  });
}
