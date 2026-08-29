import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_media_controller_stats.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Phase 15 — ≥50 content transitions under mixed / stress scenarios.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adsOff = HumorAdsSettings(
    enabled: false,
    contentInterval: 999,
    minInterval: 999,
    maxInterval: 999,
  );

  List<HumorContent> stressCatalog({required int count}) {
    const ytIds = <String>[
      'dQw4w9WgXcQ',
      '1DAd52daBNA',
      'jNQXAC9IVRw',
      'kJQP7kiw5Fk',
      '9bZkp7q19f0',
    ];
    final out = <HumorContent>[];
    for (var i = 0; i < count; i++) {
      final kind = i % 7;
      switch (kind) {
        case 0:
          final id = ytIds[i % ytIds.length];
          out.add(
            HumorContent(
              contentId: 'ext_youtube_${id}_$i',
              type: HumorContentType.video,
              language: 'tr',
              category: HumorCategory.silly,
              provider: 'youtube',
              sourceId: id,
              textBody: 'YouTube stress $i',
              downloadUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
              thumbUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
              embedUrl: 'https://www.youtube.com/embed/$id',
              sourceUrl: 'https://www.youtube.com/watch?v=$id',
              attributionRequired: true,
              aspectRatio: 16 / 9,
            ),
          );
        case 1:
          out.add(
            HumorContent(
              contentId: 'stress_giphy_$i',
              type: HumorContentType.video,
              language: 'tr',
              category: HumorCategory.meme,
              provider: 'giphy',
              sourceId: 'g$i',
              textBody: 'GIPHY stress $i',
              downloadUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
              thumbUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
              attributionRequired: true,
              aspectRatio: 16 / 9,
            ),
          );
        case 2:
          final id = ytIds[(i + 1) % ytIds.length];
          out.add(
            HumorContent(
              contentId: 'ext_youtube_b_${id}_$i',
              type: HumorContentType.video,
              language: 'tr',
              category: HumorCategory.dry,
              provider: 'youtube',
              sourceId: id,
              textBody: 'YT after GIPHY $i',
              downloadUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
              thumbUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
              embedUrl: 'https://www.youtube.com/embed/$id',
              attributionRequired: true,
              aspectRatio: 16 / 9,
            ),
          );
        case 3:
          out.add(
            HumorContent(
              contentId: 'stress_vid_$i',
              type: HumorContentType.video,
              language: 'tr',
              category: HumorCategory.absurd,
              textBody: 'Video stress $i',
              downloadUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
              thumbUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
              aspectRatio: 16 / 9,
            ),
          );
        case 4:
          out.add(
            HumorContent(
              contentId: 'stress_vid_b_$i',
              type: HumorContentType.video,
              language: 'tr',
              category: HumorCategory.situational,
              textBody: 'Video B stress $i',
              downloadUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
              thumbUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
              aspectRatio: 16 / 9,
            ),
          );
        case 5:
          out.add(
            HumorContent(
              contentId: 'stress_img_$i',
              type: HumorContentType.image,
              language: 'tr',
              category: HumorCategory.sarcasm,
              textBody: 'Image stress $i',
              aspectRatio: 9 / 16,
            ),
          );
        default:
          out.add(
            HumorContent(
              contentId: 'stress_vid_c_$i',
              type: HumorContentType.video,
              language: 'tr',
              category: HumorCategory.teasing,
              textBody: 'Video after image $i',
              downloadUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
              thumbUrl:
                  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg',
              aspectRatio: 16 / 9,
            ),
          );
      }
    }
    return out;
  }

  String transitionKind(HumorContent? a, HumorContent? b) {
    if (a == null || b == null) return 'start';
    final ap = a.isYoutube
        ? 'yt'
        : a.isGiphy
            ? 'giphy'
            : a.type == HumorContentType.video
                ? 'video'
                : 'image';
    final bp = b.isYoutube
        ? 'yt'
        : b.isGiphy
            ? 'giphy'
            : b.type == HumorContentType.video
                ? 'video'
                : 'image';
    return '$ap->$bp';
  }

  testWidgets('Phase 15: 50+ transitions — no crash / freeze / controller leak', (
    tester,
  ) async {
    HumorMediaControllerStats.reset();
    HumorContentPlayer.debugDisableHeavyMedia = true;
    HumorContentPlayer.debugTrackStubControllers = true;
    addTearDown(() {
      HumorContentPlayer.debugDisableHeavyMedia = false;
      HumorContentPlayer.debugTrackStubControllers = false;
      HumorMediaControllerStats.reset();
    });

    final catalog = stressCatalog(count: 64);
    final source = MockHumorDataSource(seed: catalog);
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adsSettings: adsOff,
      isPremium: true,
    );
    addTearDown(controller.dispose);

    final mediaErrors = <String>[];
    final transitionKinds = <String>{};
    final latencies = <int>[];
    final sw = Stopwatch()..start();
    var freezeSuspects = 0;
    var transitions = 0;

    await tester.runAsync(() async {
      await controller.load();
    });
    expect(controller.state.items, isNotEmpty);

    // Single active player — mirrors production "only current page isActive".
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final item = controller.state.current;
                if (item == null) {
                  return const SizedBox.shrink();
                }
                return HumorContentPlayer(
                  content: item,
                  isActive: true,
                  replayToken: controller.state.replayToken,
                  mediaLoadTimeout: const Duration(milliseconds: 200),
                  onMediaError: mediaErrors.add,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Future<void> advance({
      required String scenario,
      Duration settle = const Duration(milliseconds: 20),
    }) async {
      final prev = controller.state.current;
      final t0 = sw.elapsedMilliseconds;
      await tester.runAsync(() async {
        if (scenario.startsWith('fast')) {
          // Fire overlapping rates like rapid swipes.
          unawaited(
            controller.rate(
              transitions.isEven ? HumorRating.funny : HumorRating.notFunny,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 8));
        } else {
          await controller.rate(
            transitions.isEven ? HumorRating.funny : HumorRating.notFunny,
          );
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
      });
      await tester.pump();
      await tester.pump(settle);
      final next = controller.state.current;
      transitionKinds.add(transitionKind(prev, next));
      final dt = sw.elapsedMilliseconds - t0;
      latencies.add(dt);
      if (dt > 5000) {
        freezeSuspects += 1;
      }
      transitions += 1;
      expect(
        tester.takeException(),
        isNull,
        reason: 'crash after $scenario #$transitions',
      );
      expect(controller.state.isLoading, isFalse);
    }

    // 1) Normal swipe
    for (var i = 0; i < 10; i++) {
      await advance(scenario: 'normal');
    }
    // 2) Fast swipe
    for (var i = 0; i < 12; i++) {
      await advance(
        scenario: 'fast',
        settle: const Duration(milliseconds: 1),
      );
    }
    // 3) Mixed media matrix (catalog cycles V/YT/Image/…)
    for (var i = 0; i < 18; i++) {
      await advance(scenario: 'mixed');
    }
    // 4) Background / resume
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 30));
    await advance(scenario: 'resume_a');
    await advance(scenario: 'resume_b');
    // 5) Slow pace (simulates slow network UX timing)
    for (var i = 0; i < 8; i++) {
      await advance(
        scenario: 'slow',
        settle: const Duration(milliseconds: 120),
      );
    }

    // Teardown widget tree → all stubs dispose.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));

    final stats = HumorMediaControllerStats.snapshot();
    final avg = latencies.isEmpty
        ? 0
        : latencies.reduce((a, b) => a + b) ~/ latencies.length;
    final maxMs =
        latencies.isEmpty ? 0 : latencies.reduce((a, b) => a > b ? a : b);

    // ignore: avoid_print
    print(
      'PHASE15_REPORT transitions=$transitions freezeSuspects=$freezeSuspects '
      'avgMs=$avg maxMs=$maxMs kinds=$transitionKinds '
      'stats=$stats mediaErrors=${mediaErrors.length}',
    );

    expect(transitions, greaterThanOrEqualTo(50));
    expect(freezeSuspects, 0, reason: 'Freeze = NO');
    expect(tester.takeException(), isNull, reason: 'Crash = NO');
    expect(stats['youtubePeak']!, lessThanOrEqualTo(1));
    expect(stats['videoPeak']!, lessThanOrEqualTo(1));
    expect(stats['youtubeLive'], 0, reason: 'Controller leak = NO');
    expect(stats['videoLive'], 0, reason: 'Controller leak = NO');
    expect(stats['youtubeDisposed'], stats['youtubeCreated']);
    expect(stats['videoDisposed'], stats['videoCreated']);
    // Cover required transition flavors from catalog cycling.
    expect(transitionKinds.any((k) => k.contains('video->video')), isTrue);
    expect(transitionKinds.any((k) => k.contains('video->image')), isTrue);
    expect(transitionKinds.any((k) => k.contains('image->video')), isTrue);
    expect(transitionKinds.any((k) => k.contains('yt->giphy')), isTrue);
    expect(transitionKinds.any((k) => k.contains('giphy->yt')), isTrue);
  });

  test('Phase 15: controller-only 50 rates stay responsive', () async {
    final source = MockHumorDataSource(seed: stressCatalog(count: 60));
    final controller = HumorController(
      repository: HumorRepositoryImpl(dataSource: source),
      adsSettings: adsOff,
      isPremium: true,
    );
    await controller.load();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      await controller.rate(i.isEven ? HumorRating.funny : HumorRating.notFunny);
      // rate() advances via unawaited future — drain microtasks/prefetch.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Drain late prefetch completions before dispose (parallel suite safety).
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!controller.state.isLoadingMore) {
        break;
      }
    }
    expect(sw.elapsedMilliseconds, lessThan(15000));
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.currentIndex, greaterThanOrEqualTo(40));
    expect(controller.state.items.length, greaterThan(12));
    controller.dispose();
    // Late async must not throw after dispose.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
