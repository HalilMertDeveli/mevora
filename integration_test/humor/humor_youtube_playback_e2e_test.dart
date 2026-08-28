// Faz 1 — Real YouTube iframe playback on device/emulator.
//
// Prerequisites:
//   node functions/scripts/qaHumorPhase1E2e.cjs
//
// Run:
//   flutter test integration_test/humor/humor_youtube_playback_e2e_test.dart \
//     -d emulator-5554 \
//     --dart-define=USE_MOCK_HUMOR=false \
//     --dart-define=HUMOR_LAB_ENABLED=true

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_media_controller_stats.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class _LiveItem {
  _LiveItem({
    required this.contentId,
    required this.videoId,
    required this.embedUrl,
    required this.thumbUrl,
  });

  factory _LiveItem.fromJson(Map<String, dynamic> json) {
    return _LiveItem(
      contentId: json['contentId'] as String,
      videoId: json['videoId'] as String,
      embedUrl: json['embedUrl'] as String? ?? '',
      thumbUrl: json['thumbUrl'] as String? ?? '',
    );
  }

  final String contentId;
  final String videoId;
  final String embedUrl;
  final String thumbUrl;

  HumorContent toContent() {
    return HumorContent.sanitized(
      contentId: contentId,
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      provider: 'youtube',
      sourceId: videoId,
      embedUrl: embedUrl.isNotEmpty
          ? embedUrl
          : 'https://www.youtube.com/embed/$videoId?playsinline=1',
      thumbUrl: thumbUrl.isNotEmpty
          ? thumbUrl
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      downloadUrl: thumbUrl.isNotEmpty
          ? thumbUrl
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      attributionRequired: true,
      aspectRatio: 9 / 16,
    );
  }
}

Future<List<_LiveItem>> loadLiveItems() async {
  const assetPath = 'integration_test/fixtures/humor_e2e_live_ids.json';
  String raw;
  try {
    raw = await rootBundle.loadString(assetPath);
  } catch (_) {
    fail(
      'Missing $assetPath — run functions/scripts/qaHumorPhase1E2e.cjs first',
    );
  }
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final itemsRaw = decoded['items'] as List<dynamic>? ?? [];
  if (itemsRaw.length < 5) {
    fail('Need at least 5 live YouTube items in humor_e2e_live_ids.json');
  }
  return itemsRaw
      .map((e) => _LiveItem.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // REAL PATH — never stub heavy media in this file.
  HumorContentPlayer.debugDisableHeavyMedia = false;
  HumorContentPlayer.debugTrackStubControllers = false;

  testWidgets('Faz 1: real YouTube iframe init/play/pause/dispose (5 videos)', (
    tester,
  ) async {
    final items = await loadLiveItems();
    HumorMediaControllerStats.reset();

    var initialized = 0;
    for (final item in items.take(5)) {
      final content = item.toContent();
      await pumpPlayer(tester, content: content, isActive: true);

      var ready = false;
      for (var tick = 0; tick < 45; tick++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(YoutubePlayer).evaluate().isNotEmpty) {
          ready = true;
          break;
        }
        if (find.textContaining('yüklenemedi').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(ready, isTrue, reason: 'YoutubePlayer not ready for ${item.videoId}');
      initialized++;

      // Pause via deactivate
      await pumpPlayer(tester, content: content, isActive: false);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);
    }

    expect(initialized, greaterThanOrEqualTo(5));
    expect(HumorMediaControllerStats.youtubeLive, 0);
  });

  testWidgets('Faz 1: 20 real YouTube transitions without crash/freeze', (
    tester,
  ) async {
    final items = await loadLiveItems();
    if (items.length < 10) {
      fail('Need at least 10 live items for 20-transition stress');
    }
    HumorMediaControllerStats.reset();

    final catalog = <HumorContent>[];
    for (var i = 0; i < 20; i++) {
      catalog.add(items[i % items.length].toContent().copyWithIdSuffix('_$i'));
    }

    HumorContent? active;
    for (var i = 0; i < catalog.length; i++) {
      final next = catalog[i];
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

    expect(HumorMediaControllerStats.youtubeLive, 0);
    expect(HumorMediaControllerStats.youtubePeak, lessThanOrEqualTo(1));
  });
}

extension on HumorContent {
  HumorContent copyWithIdSuffix(String suffix) {
    return HumorContent(
      contentId: '$contentId$suffix',
      type: type,
      language: language,
      category: category,
      humorTags: humorTags,
      textBody: textBody,
      downloadUrl: downloadUrl,
      thumbUrl: thumbUrl,
      embedUrl: embedUrl,
      durationMs: durationMs,
      aspectRatio: aspectRatio,
      provider: provider,
      sourceId: sourceId,
      attributionRequired: attributionRequired,
      sourceUrl: sourceUrl,
    );
  }
}
