import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: Scaffold(body: SizedBox(width: 360, height: 640, child: child)),
    );
  }

  testWidgets('invalid youtube id reports media error (no crash)', (tester) async {
    String? errored;
    const bad = HumorContent(
      contentId: 'ext_youtube_badid!!!!',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.meme,
      provider: 'youtube',
      sourceId: 'bad!',
      embedUrl: 'https://www.youtube.com/embed/bad!',
      thumbUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    );

    await tester.pumpWidget(
      wrap(
        HumorContentPlayer(
          content: bad,
          isActive: true,
          onMediaError: (id) => errored = id,
          mediaLoadTimeout: const Duration(milliseconds: 50),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(tester.takeException(), isNull);
    expect(errored, bad.contentId);
  });

  testWidgets('load timeout fires media error instead of infinite spinner', (
    tester,
  ) async {
    String? errored;
    // Giphy-like URL that will fail to initialize quickly in tests.
    const stuck = HumorContent(
      contentId: 'ext_giphy_timeout_test',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      provider: 'giphy',
      sourceId: 'timeout_test',
      downloadUrl: 'https://127.0.0.1:9/does-not-exist.mp4',
      thumbUrl: null,
    );

    await tester.pumpWidget(
      wrap(
        HumorContentPlayer(
          content: stuck,
          isActive: true,
          onMediaError: (id) => errored = id,
          mediaLoadTimeout: const Duration(milliseconds: 80),
        ),
      ),
    );
    await tester.pump();
    // Allow initialize attempt + watchdog.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(errored, stuck.contentId);
  });

  testWidgets('youtube html downloadUrl is not fed to VideoPlayer', (tester) async {
    HumorContentPlayer.debugDisableHeavyMedia = true;
    addTearDown(() {
      HumorContentPlayer.debugDisableHeavyMedia = false;
    });
    String? errored;
    final poisoned = HumorContent.sanitized(
      contentId: 'ext_youtube_abcdefghijk',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.meme,
      provider: 'youtube',
      sourceId: 'abcdefghijk',
      downloadUrl: 'https://www.youtube.com/embed/abcdefghijk',
      thumbUrl: 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg',
      embedUrl: 'https://www.youtube.com/embed/abcdefghijk',
    );

    await tester.pumpWidget(
      wrap(
        HumorContentPlayer(
          content: poisoned,
          isActive: true,
          onMediaError: (id) => errored = id,
          mediaLoadTimeout: const Duration(milliseconds: 200),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(poisoned.downloadUrl?.contains('youtube.com/embed'), isFalse);
    expect(errored == null || errored == poisoned.contentId, isTrue);
  });
}
