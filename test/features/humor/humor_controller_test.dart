import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';

void main() {
  HumorController buildController(MockHumorDataSource source) {
    return HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
    );
  }

  test('load populates feed from mock datasource', () async {
    final source = MockHumorDataSource();
    final controller = buildController(source);

    await controller.load();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.failure, isNull);
    expect(controller.state.items, isNotEmpty);
    expect(controller.state.current?.contentId, 'hc_tr_vid_001');
    expect(controller.state.current?.type, HumorContentType.video);
    expect(controller.state.current?.language, 'tr');
    expect(controller.state.current?.hasMedia, isTrue);
    expect(source.feedCalls, 1);
  });

  test('rate advances index and enables undo', () async {
    final source = MockHumorDataSource();
    final controller = buildController(source);
    await controller.load();

    await controller.rate(HumorRating.veryFunny);

    expect(controller.state.currentIndex, 1);
    expect(controller.state.canUndo, isTrue);
    expect(controller.state.lastRated, HumorRating.veryFunny);
    expect(source.feedbackCalls, 1);
    expect(source.profile.interactionCount, 1);
  });

  test('undo returns to previous item', () async {
    final source = MockHumorDataSource();
    final controller = buildController(source);
    await controller.load();
    await controller.rate(HumorRating.funny);
    expect(controller.state.currentIndex, 1);

    await controller.undo();

    expect(controller.state.currentIndex, 0);
    expect(controller.state.canUndo, isFalse);
  });

  test('empty feed surfaces empty state', () async {
    final source = MockHumorDataSource(seed: const <HumorContent>[]);
    final controller = buildController(source);

    await controller.load();

    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.items, isEmpty);
  });

  test('feed error surfaces failure', () async {
    final source = MockHumorDataSource()..failFeed = true;
    final controller = buildController(source);

    await controller.load();

    expect(controller.state.failure, isNotNull);
    expect(controller.state.items, isEmpty);
    expect(controller.state.isLoading, isFalse);
  });
}
