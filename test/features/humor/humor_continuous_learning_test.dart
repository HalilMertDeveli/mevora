import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_daily_controller.dart';

void main() {
  HumorController build(MockHumorDataSource source) =>
      HumorController(repository: HumorRepositoryImpl(dataSource: source));

  HumorDailyController buildDaily(MockHumorDataSource source) =>
      HumorDailyController(repository: HumorRepositoryImpl(dataSource: source));

  test('learning continues past the calibration milestone, five items a day, '
      'on the same profile', () async {
    final source = MockHumorDataSource();
    final controller = build(source);
    await controller.load();
    final total = controller.state.calibration.totalCount;

    for (var i = 0; i < total; i += 1) {
      await controller.rate(HumorRating.funny);
    }
    final atMilestone = controller.state.profile;
    expect(controller.state.calibration.complete, isTrue);

    // Nothing more today: the feed is closed and the tour starts tomorrow.
    await controller.load();
    expect(controller.state.current, isNull);
    final sameDay = buildDaily(source);
    await sameDay.load();
    expect(sameDay.state.set?.startsTomorrow, isTrue);

    // The next day brings the next five of the sequence.
    source.closeDay('2099-01-02');
    final daily = buildDaily(source);
    await daily.load();
    expect(daily.state.total, MockHumorDataSource.dailySetSize);
    expect(
      daily.state.set!.items.map((item) => item.contentId),
      source.sequenceIds.sublist(total, total + 5),
    );
    var extra = 0;
    while (daily.state.current != null) {
      await daily.rate(HumorRating.veryFunny);
      extra += 1;
    }

    expect(extra, MockHumorDataSource.dailySetSize);
    expect(daily.state.completed, isTrue);
    expect(
      source.profile.interactionCount,
      atMilestone.interactionCount + extra,
    );
    expect(source.profile.confidence, greaterThan(atMilestone.confidence));
    // The milestone itself stays frozen.
    expect(source.calibration.completedCount, total);
  });

  test('a member who is through the whole sequence is told so, not shown '
      'something broken', () async {
    final source = MockHumorDataSource()..completeCalibration();
    final repository = HumorRepositoryImpl(dataSource: source);

    // Day after day until nothing is left.
    HumorDailySet? set;
    for (var day = 2; day < 40; day += 1) {
      source.closeDay('2099-01-${day.toString().padLeft(2, '0')}');
      set = (await repository.getDailySet()).valueOrNull;
      if (set == null || !set.isReady) {
        break;
      }
      expect(set.total, lessThanOrEqualTo(MockHumorDataSource.dailySetSize));
      for (final item in set.items) {
        await source.submitDailyResponse(
          dayId: set.dayId,
          contentId: item.contentId,
          rating: HumorRating.funny,
        );
      }
    }

    expect(set?.sequenceComplete, isTrue);
    expect(
      source.profile.interactionCount,
      MockHumorDataSource.seedCatalog.length,
    );

    final controller = build(source);
    await controller.load();
    expect(controller.state.items, isEmpty);
    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.catalogExhausted, isTrue);
    expect(
      controller.state.catalogEmpty,
      isFalse,
      reason: 'the catalog is not empty, it is all seen',
    );
  });

  test(
    'an empty catalog is reported as our problem, not the user\'s',
    () async {
      final source = MockHumorDataSource(seed: const <HumorContent>[]);
      final controller = build(source);
      await controller.load();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.catalogEmpty, isTrue);
      expect(controller.state.catalogExhausted, isFalse);
    },
  );
}
