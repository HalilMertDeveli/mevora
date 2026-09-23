import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';

void main() {
  HumorController build(MockHumorDataSource source) =>
      HumorController(repository: HumorRepositoryImpl(dataSource: source));

  test('learning continues well past the calibration milestone', () async {
    final source = MockHumorDataSource();
    final controller = build(source);
    await controller.load();

    for (var i = 0; i < HumorCalibration.totalInteractions; i += 1) {
      await controller.rate(HumorRating.funny);
    }
    final atMilestone = controller.state.profile;
    expect(controller.state.calibration.complete, isTrue);

    // Keep going into the ordinary feed.
    await controller.load();
    var extra = 0;
    while (controller.state.current != null && extra < 4) {
      await controller.rate(HumorRating.veryFunny);
      extra += 1;
    }

    expect(extra, greaterThan(0), reason: 'no content left to learn from');
    expect(
      controller.state.profile.interactionCount,
      atMilestone.interactionCount + extra,
    );
    expect(
      controller.state.profile.confidence,
      greaterThan(atMilestone.confidence),
    );
    // The milestone itself stays frozen.
    expect(
      controller.state.calibration.completedCount,
      HumorCalibration.totalInteractions,
    );
  });

  test('a fully rated catalog reports being caught up, not broken', () async {
    final source = MockHumorDataSource();
    final controller = build(source);

    // Rate everything the mock can serve.
    for (final item in MockHumorDataSource.seedCatalog) {
      await source.submitFeedback(
        contentId: item.contentId,
        rating: HumorRating.funny,
      );
    }
    await controller.load();

    expect(controller.state.items, isEmpty);
    expect(controller.state.isEmpty, isTrue);
    expect(
      controller.state.catalogExhausted,
      isTrue,
      reason: 'the user finished the catalog — that is an achievement',
    );
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
