import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:video_player/video_player.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _mp4 =
    'https://static.klipy.com/ii/0123456789abcdef0123456789abcdef/aa/bb/video.mp4';
const _preview =
    'https://static.klipy.com/ii/0123456789abcdef0123456789abcdef/aa/bb/preview.webp';

/// A curated KLIPY clip exactly as `getDailyHumorSet` / `getHumorFeed` send
/// it: a video card whose credit names the provider and nobody else.
Map<String, Object?> _klipyItem({Object? thumbUrl = _preview}) => {
  'contentId': 'hc_klipy_1000000000000001',
  'type': 'video',
  'language': 'en',
  'category': 'sarcasm',
  'humorTags': <String>[],
  'media': {
    'downloadUrl': _mp4,
    'thumbUrl': thumbUrl,
    'durationMs': 2460,
    'aspectRatio': 2.388,
    'textBody': null,
  },
  'attribution': {
    'provider': 'klipy',
    'displayName': null,
    'username': null,
    'sourceUrl': 'https://klipy.com/clips/fixture-clip',
    'verified': false,
  },
};

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, height: 560, child: child)),
    ),
  );
}

/// A controller that never touches the platform: the test decides how
/// initialisation ends.
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController(super.url) : super.networkUrl();

  final _init = Completer<void>();
  var disposed = false;

  @override
  Future<void> initialize() => _init.future;

  void completeInit() {
    if (!disposed) {
      value = value.copyWith(
        isInitialized: true,
        size: const Size(1280, 536),
        duration: const Duration(milliseconds: 2460),
      );
    }
    _init.complete();
  }

  void failInit() => _init.completeError(StateError('network down'));

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class _Controllers {
  final created = <_FakeVideoController>[];
  final urls = <Uri>[];

  VideoPlayerController call(Uri uri) {
    urls.add(uri);
    final controller = _FakeVideoController(uri);
    created.add(controller);
    return controller;
  }
}

Finder get _spinner => find.byType(MevoraOrbitLoader);
Finder get _next => find.widgetWithText(FilledButton, _en.humorMediaNext);

void main() {
  group('KLIPY credit', () {
    test('the provider is spelled KLIPY and the label is the provider '
        'alone', () {
      const attribution = HumorContentAttribution(provider: 'klipy');
      expect(attribution.providerLabel, 'KLIPY');
      expect(attribution.creatorLabel, isNull);
      expect(attribution.label, 'KLIPY');
      expect(
        const HumorContentAttribution(provider: 'KLIPY').providerLabel,
        'KLIPY',
      );
    });

    test('GIPHY and unknown providers read as they always did', () {
      expect(
        const HumorContentAttribution(
          provider: 'giphy',
          username: 'funnyperson',
        ).label,
        'GIPHY · @funnyperson',
      );
      expect(const HumorContentAttribution(provider: 'tenor').label, 'Tenor');
      expect(
        const HumorContentAttribution(provider: 'acme').providerLabel,
        'acme',
      );
    });

    test('a served KLIPY clip parses to a video with the KLIPY credit', () {
      final content = HumorContent.tryParseFeedItem(_klipyItem())!;
      expect(content.type, HumorContentType.video);
      expect(content.downloadUrl, _mp4);
      expect(content.thumbUrl, _preview);
      expect(content.durationMs, 2460);
      expect(content.textBody, isNull);
      expect(content.attribution!.provider, 'klipy');
      expect(content.attribution!.label, 'KLIPY');
      expect(content.attribution!.verified, isFalse);
      expect(
        content.attribution!.sourceUrl,
        'https://klipy.com/clips/fixture-clip',
      );
    });
  });

  group('KLIPY clip playback', () {
    testWidgets('takes the video path: the MP4 goes to the video player, '
        'never to an image', (tester) async {
      final content = HumorContent.tryParseFeedItem(_klipyItem())!;
      expect(HumorContentPlayer.isVideoContent(content), isTrue);
      // The still warmed for upcoming cards is the preview, not the clip.
      expect(HumorContentPlayer.stillUrlFor(content), _preview);

      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: content,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      expect(controllers.urls, [Uri.parse(_mp4)]);
      expect(_spinner, findsOneWidget);
      expect(find.text('KLIPY'), findsOneWidget);
      expect(find.byIcon(MevoraIcons.verified), findsNothing);

      controllers.created.single.completeInit();
      await tester.pump();
      await tester.pump();
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(_spinner, findsNothing);
      expect(find.text('KLIPY'), findsOneWidget);
    });

    testWidgets('a clip without a poster shows the loading state, then '
        'plays', (tester) async {
      final content = HumorContent.tryParseFeedItem(
        _klipyItem(thumbUrl: null),
      )!;
      expect(content.thumbUrl, isNull);
      expect(HumorContentPlayer.stillUrlFor(content), isNull);

      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: content,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_spinner, findsOneWidget);
      expect(find.byType(Image), findsNothing);

      controllers.created.single.completeInit();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(VideoPlayer), findsOneWidget);
    });

    testWidgets('a clip that cannot load offers Next after one silent '
        'retry', (tester) async {
      final content = HumorContent.tryParseFeedItem(
        _klipyItem(thumbUrl: null),
      )!;
      final controllers = _Controllers();
      final skipped = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: content,
            onMediaError: (_) {},
            onSkipUnplayable: skipped.add,
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      controllers.created.single.failInit();
      await tester.pump();
      await tester.pump(HumorContentPlayer.autoRetryDelay);
      await tester.pump();
      expect(controllers.created, hasLength(2), reason: 'one silent retry');
      expect(_next, findsNothing);

      controllers.created.last.failInit();
      for (var i = 0; i < 20 && _next.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text(_en.humorVideoLoadFailed), findsOneWidget);
      expect(_next, findsOneWidget);
      expect(find.text('KLIPY'), findsOneWidget);

      await tester.tap(_next);
      await tester.pump();
      expect(skipped, ['hc_klipy_1000000000000001']);
    });
  });
}
