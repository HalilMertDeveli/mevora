import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _caption = 'When the build is green on the first try';
const _clipUrl = 'https://cdn.example.test/humor/clip.mp4';
const _thumbUrl = 'https://cdn.example.test/humor/clip-thumb.jpg';

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

HumorContent _video({
  String contentId = 'clip-1',
  String? downloadUrl = _clipUrl,
  String? thumbUrl,
  String? textBody = _caption,
  double? aspectRatio,
}) {
  return HumorContent(
    contentId: contentId,
    type: HumorContentType.video,
    language: 'en',
    category: HumorCategory.absurd,
    textBody: textBody,
    downloadUrl: downloadUrl,
    thumbUrl: thumbUrl,
    aspectRatio: aspectRatio,
  );
}

/// A controller that never touches the platform: the test decides when (and
/// how) initialisation ends.
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController(super.url, {this.size = const Size(1280, 720)})
    : super.networkUrl();

  final Size size;
  final _init = Completer<void>();
  var initializeCalls = 0;
  var playCalls = 0;
  var pauseCalls = 0;
  final seeks = <Duration>[];
  var disposed = false;

  @override
  Future<void> initialize() {
    initializeCalls++;
    return _init.future;
  }

  void completeInit() {
    if (!disposed) {
      value = value.copyWith(
        isInitialized: true,
        size: size,
        duration: const Duration(seconds: 8),
      );
    }
    _init.complete();
  }

  void failInit() => _init.completeError(StateError('network down'));

  @override
  Future<void> play() async {
    playCalls++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
  }

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
  _Controllers({this.size = const Size(1280, 720)});

  Size size;
  final created = <_FakeVideoController>[];

  VideoPlayerController call(Uri uri) {
    final controller = _FakeVideoController(uri, size: size);
    created.add(controller);
    return controller;
  }
}

Finder get _spinner => find.byType(CircularProgressIndicator);

VideoPlayerController? _boundController(WidgetTester tester) {
  final finder = find.byType(VideoPlayer);
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<VideoPlayer>(finder).controller;
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('an image renders with its caption once, and a failed load '
      'falls back to the text once', (tester) async {
    final errors = <String>[];
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: const HumorContent(
            contentId: 'meme-1',
            type: HumorContentType.meme,
            language: 'en',
            category: HumorCategory.meme,
            textBody: _caption,
            downloadUrl: 'https://cdn.example.test/humor/meme-1.jpg',
            aspectRatio: 1,
          ),
          onMediaError: errors.add,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain, reason: 'a square meme is not cropped');
    expect(find.text(_caption), findsOneWidget);
    expect(find.text(_en.humorMediaUnavailable), findsNothing);

    // flutter_test answers every HTTP request with a 400, so the load fails.
    await _pumpUntilFound(tester, find.text(_en.humorMediaUnavailable));
    await tester.pump();

    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
    expect(find.text(_en.humorEmptyFeed), findsNothing);
    expect(errors, ['meme-1']);
  });

  testWidgets('a portrait image fills the card', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const HumorContentPlayer(
          content: HumorContent(
            contentId: 'meme-2',
            type: HumorContentType.image,
            language: 'en',
            category: HumorCategory.meme,
            downloadUrl: 'https://cdn.example.test/humor/meme-2.jpg',
            aspectRatio: 9 / 16,
          ),
        ),
      ),
    );

    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
  });

  testWidgets('a video that fails to load shows the fallback, not a spinner, '
      'even without a thumbnail', (tester) async {
    final controllers = _Controllers();
    final errors = <String>[];
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(),
          onMediaError: errors.add,
          videoControllerFactory: controllers.call,
        ),
      ),
    );
    expect(_spinner, findsOneWidget);

    controllers.created.single.failInit();
    await tester.pump();
    await tester.pump();

    expect(_spinner, findsNothing);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(controllers.created.single.disposed, isTrue);
    expect(errors, ['clip-1']);
  });

  testWidgets('a long caption in the fallback never overflows the card', (
    tester,
  ) async {
    final longCaption = List.filled(
      80,
      'unexpectedly long punchline',
    ).join(' ');
    final controllers = _Controllers();
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(textBody: longCaption),
          videoControllerFactory: controllers.call,
        ),
      ),
    );

    controllers.created.single.failInit();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(find.text(longCaption), findsOneWidget);
  });

  testWidgets('a video without a playable URL falls back at once', (
    tester,
  ) async {
    final controllers = _Controllers();
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(downloadUrl: null),
          videoControllerFactory: controllers.call,
        ),
      ),
    );

    expect(controllers.created, isEmpty);
    expect(_spinner, findsNothing);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
  });

  testWidgets('a stalled video gives up at the timeout', (tester) async {
    final controllers = _Controllers();
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(textBody: null),
          videoControllerFactory: controllers.call,
        ),
      ),
    );

    await tester.pump(
      HumorContentPlayer.videoInitTimeout - const Duration(seconds: 1),
    );
    expect(_spinner, findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(_spinner, findsNothing);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(controllers.created.single.disposed, isTrue);
  });

  testWidgets('a zero-size video falls back instead of a blank black card', (
    tester,
  ) async {
    final controllers = _Controllers(size: Size.zero);
    final errors = <String>[];
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(),
          onMediaError: errors.add,
          videoControllerFactory: controllers.call,
        ),
      ),
    );

    controllers.created.single.completeInit();
    await tester.pump();
    await tester.pump();

    expect(find.byType(VideoPlayer), findsNothing);
    expect(_spinner, findsNothing);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(controllers.created.single.disposed, isTrue);
    expect(errors, ['clip-1']);
  });

  testWidgets('a broken video shows its thumbnail, never the mp4 as an image', (
    tester,
  ) async {
    final controllers = _Controllers();
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(thumbUrl: _thumbUrl),
          videoControllerFactory: controllers.call,
        ),
      ),
    );

    controllers.created.single.failInit();
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    final provider = images.single.image;
    expect(provider, isA<NetworkImage>());
    expect((provider as NetworkImage).url, _thumbUrl);
    expect(_spinner, findsNothing);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);

    // The thumbnail fails too (HTTP 400 in tests): still one caption.
    await _pumpUntilFound(tester, find.byIcon(Icons.hide_image_outlined));
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
  });

  testWidgets('landscape video is letterboxed, portrait video fills the card', (
    tester,
  ) async {
    final controllers = _Controllers();
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(),
          videoControllerFactory: controllers.call,
        ),
      ),
    );
    controllers.created.single.completeInit();
    await tester.pump();

    expect(_spinner, findsNothing);
    expect(_boundController(tester), same(controllers.created.single));
    expect(
      tester.widget<FittedBox>(find.byType(FittedBox)).fit,
      BoxFit.contain,
    );
    expect(controllers.created.single.playCalls, 1);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);

    controllers.size = const Size(720, 1280);
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(contentId: 'clip-2'),
          videoControllerFactory: controllers.call,
        ),
      ),
    );
    controllers.created.last.completeInit();
    await tester.pump();

    expect(_boundController(tester), same(controllers.created.last));
    expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.cover);
  });

  testWidgets('a content change mid-load binds only the new clip', (
    tester,
  ) async {
    final controllers = _Controllers();
    Widget player(HumorContent content) => _wrap(
      HumorContentPlayer(
        content: content,
        videoControllerFactory: controllers.call,
      ),
    );

    await tester.pumpWidget(player(_video(contentId: 'first')));
    await tester.pumpWidget(
      player(
        _video(
          contentId: 'second',
          downloadUrl: 'https://cdn.example.test/humor/second.mp4',
        ),
      ),
    );
    await tester.pump();

    expect(controllers.created, hasLength(2));
    final first = controllers.created.first;
    final second = controllers.created.last;
    expect(second.dataSource, 'https://cdn.example.test/humor/second.mp4');
    expect(first.disposed, isTrue, reason: 'the abandoned load is released');

    second.completeInit();
    await tester.pump();
    expect(_boundController(tester), same(second));

    // The first clip resolving late must not replace the second.
    first.completeInit();
    await tester.pump();
    await tester.pump();
    expect(_boundController(tester), same(second));
    expect(second.disposed, isFalse);
  });

  testWidgets('replay seeks the loaded clip; an off-screen card pauses and '
      'ignores replays', (tester) async {
    final controllers = _Controllers();
    Widget player({required bool isActive, required int replayToken}) => _wrap(
      HumorContentPlayer(
        content: _video(),
        isActive: isActive,
        replayToken: replayToken,
        videoControllerFactory: controllers.call,
      ),
    );

    await tester.pumpWidget(player(isActive: true, replayToken: 0));
    final clip = controllers.created.single;
    clip.completeInit();
    await tester.pump();
    expect(clip.playCalls, 1);

    await tester.pumpWidget(player(isActive: true, replayToken: 1));
    await tester.pump();
    expect(clip.seeks, [Duration.zero]);
    expect(clip.playCalls, 2);
    expect(controllers.created, hasLength(1), reason: 'no re-download');
    expect(clip.initializeCalls, 1);

    await tester.pumpWidget(player(isActive: false, replayToken: 1));
    await tester.pump();
    expect(clip.pauseCalls, 1);

    await tester.pumpWidget(player(isActive: false, replayToken: 2));
    await tester.pump();
    expect(clip.seeks, [Duration.zero]);
    expect(clip.playCalls, 2);
    expect(controllers.created, hasLength(1));
    expect(_boundController(tester), same(clip));
  });

  testWidgets('a clip that breaks while playing falls back', (tester) async {
    final controllers = _Controllers();
    final errors = <String>[];
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(),
          onMediaError: errors.add,
          videoControllerFactory: controllers.call,
        ),
      ),
    );
    final clip = controllers.created.single..completeInit();
    await tester.pump();
    expect(_boundController(tester), same(clip));

    clip.value = clip.value.copyWith(errorDescription: 'decoder died');
    await tester.pump();
    await tester.pump();

    expect(find.byType(VideoPlayer), findsNothing);
    expect(_spinner, findsNothing);
    expect(find.text(_en.humorMediaUnavailable), findsOneWidget);
    expect(clip.disposed, isTrue);
    expect(errors, ['clip-1']);
  });

  testWidgets('dispose releases the bound controller', (tester) async {
    final controllers = _Controllers();
    await tester.pumpWidget(
      _wrap(
        HumorContentPlayer(
          content: _video(),
          videoControllerFactory: controllers.call,
        ),
      ),
    );
    controllers.created.single.completeInit();
    await tester.pump();
    expect(controllers.created.single.disposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(controllers.created.single.disposed, isTrue);
  });

  testWidgets(
    'dispose mid-load releases the pending controller and its timer',
    (tester) async {
      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(controllers.created.single.disposed, isTrue);
      // flutter_test fails the test if the load timeout were still pending.
    },
  );
}
