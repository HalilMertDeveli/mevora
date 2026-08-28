import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_media_controller_stats.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Regression — rapid active/inactive swaps must keep youtubePeak <= 1.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HumorContent youtubeAt(int i) {
    const id = 'dQw4w9WgXcQ';
    return HumorContent(
      contentId: 'ext_youtube_lifecycle_$i',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      provider: 'youtube',
      sourceId: id,
      embedUrl: 'https://www.youtube.com/embed/$id',
      downloadUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      thumbUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      attributionRequired: true,
      aspectRatio: 9 / 16,
    );
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required HumorContent content,
    required bool isActive,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 844,
            child: HumorContentPlayer(
              key: ValueKey(content.contentId),
              content: content,
              isActive: isActive,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    HumorMediaControllerStats.reset();
    HumorContentPlayer.debugDisableHeavyMedia = true;
    HumorContentPlayer.debugTrackStubControllers = true;
  });

  tearDown(() {
    HumorContentPlayer.debugDisableHeavyMedia = false;
    HumorContentPlayer.debugTrackStubControllers = false;
    HumorMediaControllerStats.reset();
  });

  testWidgets('rapid widget swaps keep youtubePeak <= 1', (tester) async {
    HumorContent? active;
    for (var i = 0; i < 20; i++) {
      final next = youtubeAt(i);
      if (active != null) {
        await pumpPlayer(tester, content: active, isActive: false);
        await tester.pump(const Duration(milliseconds: 300));
      }
      active = next;
      await pumpPlayer(tester, content: active, isActive: true);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }

    if (active != null) {
      await pumpPlayer(tester, content: active, isActive: false);
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));
    expect(HumorMediaControllerStats.youtubeLive, 0);
  });

  testWidgets('rapid isActive toggles on same widget keep youtubePeak <= 1', (
    tester,
  ) async {
    final content = youtubeAt(0);
    await pumpPlayer(tester, content: content, isActive: true);
    await tester.pump(const Duration(milliseconds: 50));

    for (var i = 0; i < 20; i++) {
      await pumpPlayer(tester, content: content, isActive: false);
      await tester.pump(const Duration(milliseconds: 50));
      await pumpPlayer(tester, content: content, isActive: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }

    await pumpPlayer(tester, content: content, isActive: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));
    expect(HumorMediaControllerStats.youtubeLive, 0);
  });
}
