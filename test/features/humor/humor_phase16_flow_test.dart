import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';

/// Phase 16 — Flutter Humor Lab automated flow coverage.
void main() {
  const adsOff = HumorAdsSettings(
    enabled: false,
    contentInterval: 999,
    minInterval: 999,
    maxInterval: 999,
  );

  HumorController build(MockHumorDataSource source) {
    return HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adsSettings: adsOff,
      isPremium: true,
    );
  }

  const singleYt = HumorContent(
    contentId: 'ext_youtube_dQw4w9WgXcQ',
    type: HumorContentType.video,
    language: 'tr',
    category: HumorCategory.silly,
    provider: 'youtube',
    sourceId: 'dQw4w9WgXcQ',
    embedUrl: 'https://www.youtube.com/embed/dQw4w9WgXcQ',
    downloadUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    thumbUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    textBody: 'single youtube',
  );

  const giphy = HumorContent(
    contentId: 'ext_giphy_phase16',
    type: HumorContentType.video,
    language: 'tr',
    category: HumorCategory.meme,
    provider: 'giphy',
    sourceId: 'phase16',
    downloadUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    textBody: 'giphy clip',
  );

  const image = HumorContent(
    contentId: 'hc_phase16_img',
    type: HumorContentType.image,
    language: 'tr',
    category: HumorCategory.sarcasm,
    textBody: 'still image',
  );

  test('single video loads as current item', () async {
    final source = MockHumorDataSource(seed: const [singleYt]);
    final controller = build(source);
    await controller.load();
    expect(controller.state.failure, isNull);
    expect(controller.state.current?.contentId, singleYt.contentId);
    expect(controller.state.current?.isYoutube, isTrue);
    expect(controller.state.isLoading, isFalse);
    controller.dispose();
  });

  test('multiple videos keep ordered feed and prefetch runway', () async {
    final seed = List<HumorContent>.generate(24, (i) {
      if (i.isEven) {
        return HumorContent(
          contentId: 'ext_youtube_phase16_$i',
          type: HumorContentType.video,
          language: 'tr',
          category: HumorCategory.meme,
          provider: 'youtube',
          sourceId: 'dQw4w9WgXcQ',
          embedUrl: 'https://www.youtube.com/embed/dQw4w9WgXcQ',
          downloadUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          textBody: 'yt $i',
        );
      }
      return HumorContent(
        contentId: 'hc_vid_phase16_$i',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.absurd,
        downloadUrl:
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
        textBody: 'mp4 $i',
      );
    });
    final source = MockHumorDataSource(seed: seed);
    final controller = build(source);
    await controller.load();
    expect(controller.state.items.length, greaterThanOrEqualTo(12));
    for (var i = 0; i < 10; i++) {
      await controller.rate(HumorRating.funny);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(controller.state.currentIndex, greaterThanOrEqualTo(8));
    expect(controller.state.items.length, greaterThan(12));
    expect(controller.state.isLoading, isFalse);
    controller.dispose();
  });

  test('rating funny then not_funny advances and updates counts', () async {
    final source = MockHumorDataSource(seed: const [singleYt, giphy, image]);
    final controller = build(source);
    await controller.load();
    await controller.rate(HumorRating.funny);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.lastRated, HumorRating.funny);
    expect(source.profile.funnyCount, 1);
    await controller.rate(HumorRating.notFunny);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.lastRated, HumorRating.notFunny);
    expect(source.profile.notFunnyCount, greaterThanOrEqualTo(1));
    expect(controller.state.currentIndex, greaterThanOrEqualTo(1));
    controller.dispose();
  });

  test('next content after rate changes currentId', () async {
    final source = MockHumorDataSource(seed: const [singleYt, giphy, image]);
    final controller = build(source);
    await controller.load();
    final first = controller.state.current!.contentId;
    await controller.rate(HumorRating.funny);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(controller.state.current!.contentId, isNot(first));
    controller.dispose();
  });

  test('provider switching youtube → giphy → image', () async {
    final source = MockHumorDataSource(seed: const [singleYt, giphy, image]);
    final controller = build(source);
    await controller.load();
    expect(controller.state.current!.isYoutube, isTrue);
    await controller.rate(HumorRating.funny);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(controller.state.current!.isGiphy, isTrue);
    await controller.rate(HumorRating.notFunny);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(controller.state.current!.type, HumorContentType.image);
    controller.dispose();
  });

  test('error state: feed failure is not infinite loading', () async {
    final source = MockHumorDataSource(seed: const [singleYt])..failFeed = true;
    final controller = build(source);
    await controller.load();
    expect(controller.state.failure, isNotNull);
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.items, isEmpty);
    controller.dispose();
  });

  test('error state: broken media skip advances without crash', () async {
    // Unique ids — mock feed pageSize wraps, so skip must clear every copy.
    final source = MockHumorDataSource(
      seed: const [singleYt, giphy, image],
    );
    final controller = build(source);
    await controller.load();
    final broken = controller.state.current!.contentId;
    await controller.skipBrokenMedia(broken);
    expect(controller.state.items.any((e) => e.contentId == broken), isFalse);
    expect(controller.state.current, isNotNull);
    expect(controller.state.current!.contentId, isNot(broken));
    expect(controller.state.isLoading, isFalse);
    controller.dispose();
  });
}
