import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
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
  HumorContentAttribution? attribution,
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
    attribution: attribution,
  );
}

/// A controller that never touches the platform: the test decides when (and
/// how) initialisation ends, and where playback is.
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

  /// Playback made progress (the platform reports a new position).
  void advance(Duration by) {
    value = value.copyWith(position: value.position + by);
  }

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

class _RecordingAnalytics implements AnalyticsProvider {
  final events = <(String, Map<String, Object>?)>[];

  List<Map<String, Object>?> named(String name) => [
    for (final (event, parameters) in events)
      if (event == name) parameters,
  ];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name, parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

Finder get _spinner => find.byType(CircularProgressIndicator);
Finder get _failedMessage => find.text(_en.humorVideoLoadFailed);
Finder get _tryAgain => find.widgetWithText(OutlinedButton, _en.humorTryAgain);
Finder get _next => find.widgetWithText(FilledButton, _en.humorMediaNext);

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

/// Let a failed attempt settle and the silent retry start.
Future<void> _pumpRetry(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(HumorContentPlayer.autoRetryDelay);
  await tester.pump();
}

/// Let a failure settle into the failed state.
Future<void> _pumpFailed(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void _expectNoFailure() {
  expect(_failedMessage, findsNothing);
  expect(find.text(_en.humorMediaUnavailable), findsNothing);
}

void main() {
  group('images and text', () {
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
      expect(_next, findsNothing, reason: 'no Next without a handler');
    });

    testWidgets('a broken image offers Next when the host can skip it', (
      tester,
    ) async {
      final skipped = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: const HumorContent(
              contentId: 'meme-3',
              type: HumorContentType.image,
              language: 'en',
              category: HumorCategory.meme,
              downloadUrl: 'https://cdn.example.test/humor/meme-3.jpg',
            ),
            onSkipUnplayable: skipped.add,
          ),
        ),
      );
      await _pumpUntilFound(tester, _next);

      await tester.tap(_next);
      expect(skipped, ['meme-3']);
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

    testWidgets('a text card shows the joke and its category, never as a '
        'failure', (tester) async {
      final errors = <String>[];
      const joke = 'Kahve olmadan ben "ben" değilim.';
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: const HumorContent(
              contentId: 'mevora-text-1',
              type: HumorContentType.text,
              language: 'tr',
              category: HumorCategory.wordplay,
              textBody: joke,
            ),
            onMediaError: errors.add,
            onSkipUnplayable: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text(joke), findsOneWidget);
      expect(find.text(_en.humorCategoryWordplay), findsOneWidget);
      _expectNoFailure();
      expect(find.byIcon(Icons.hide_image_outlined), findsNothing);
      expect(find.byIcon(Icons.videocam_off_outlined), findsNothing);
      expect(find.byType(Image), findsNothing, reason: 'no fake picture');
      expect(_spinner, findsNothing);
      expect(_next, findsNothing);
      expect(errors, isEmpty);
    });

    testWidgets('a very long text card scrolls instead of overflowing', (
      tester,
    ) async {
      final joke = List.filled(60, 'a remarkably long setup').join(' ');
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: HumorContent(
              contentId: 'mevora-text-2',
              type: HumorContentType.text,
              language: 'en',
              category: HumorCategory.dry,
              textBody: joke,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(joke), findsOneWidget);
    });
  });

  group('attribution', () {
    testWidgets('a provider card credits the provider and creator', (
      tester,
    ) async {
      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(
              attribution: const HumorContentAttribution(
                provider: 'giphy',
                username: 'funnyperson',
                verified: true,
              ),
            ),
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      expect(find.text('GIPHY · @funnyperson'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.bySemanticsLabel(_en.humorAttributionVerified), findsOne);
    });

    testWidgets('an unverified creator gets no check; curated content no '
        'label', (tester) async {
      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(
              attribution: const HumorContentAttribution(
                provider: 'giphy',
                displayName: 'Some Studio',
              ),
            ),
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      expect(find.text('GIPHY · Some Studio'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsNothing);

      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(contentId: 'curated'),
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      expect(find.textContaining('GIPHY'), findsNothing);
    });
  });

  group('video state machine', () {
    testWidgets('loading shows the poster with a spinner, then plays', (
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

      expect(_spinner, findsOneWidget);
      final poster = tester.widget<Image>(find.byType(Image));
      expect((poster.image as NetworkImage).url, _thumbUrl);
      _expectNoFailure();

      final clip = controllers.created.single..completeInit();
      await tester.pump();

      expect(_spinner, findsNothing);
      expect(_boundController(tester), same(clip));
      expect(clip.playCalls, 1);
      _expectNoFailure();
    });

    testWidgets('without a poster, loading is the neutral spinner only', (
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

      expect(_spinner, findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: 'nothing fabricated');
    });

    testWidgets('an init error retries once silently, then shows the failed '
        'state with Try again and Next', (tester) async {
      final controllers = _Controllers();
      final analytics = _RecordingAnalytics();
      final errors = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            onMediaError: errors.add,
            onSkipUnplayable: (_) {},
            analytics: analytics,
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      controllers.created.single.failInit();
      await tester.pump();
      // The first failure is silent: still loading, nothing reported.
      expect(_spinner, findsOneWidget);
      _expectNoFailure();
      expect(errors, isEmpty);
      expect(controllers.created.single.disposed, isTrue);

      await _pumpRetry(tester);
      expect(controllers.created, hasLength(2), reason: 'a fresh controller');
      expect(_spinner, findsOneWidget);

      controllers.created.last.failInit();
      await _pumpFailed(tester);

      expect(_spinner, findsNothing);
      expect(_failedMessage, findsOneWidget);
      expect(find.text(_caption), findsOneWidget);
      expect(_tryAgain, findsOneWidget);
      expect(_next, findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(controllers.created.last.disposed, isTrue);
      expect(errors, ['clip-1']);
      expect(analytics.named(AnalyticsEvents.humorMediaFailed), [
        {
          'content_id': 'clip-1',
          'media': 'video',
          'reason': 'error',
          'attempt': 1,
        },
        {
          'content_id': 'clip-1',
          'media': 'video',
          'reason': 'error',
          'attempt': 2,
        },
      ]);
      expect(analytics.named(AnalyticsEvents.humorMediaRetry), [
        {'content_id': 'clip-1', 'kind': 'auto'},
      ]);

      // Nothing else is ever downloaded on its own.
      await tester.pump(const Duration(minutes: 1));
      expect(controllers.created, hasLength(2));
    });

    testWidgets('the failed state keeps the poster behind it', (tester) async {
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
      await _pumpRetry(tester);
      controllers.created.last.failInit();
      await _pumpFailed(tester);

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(1));
      expect((images.single.image as NetworkImage).url, _thumbUrl);
      expect(_failedMessage, findsOneWidget);
      expect(find.text(_caption), findsOneWidget);
      expect(_spinner, findsNothing);
    });

    testWidgets('a long caption in the failed state never overflows', (
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
            onSkipUnplayable: (_) {},
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      controllers.created.single.failInit();
      await _pumpRetry(tester);
      controllers.created.last.failInit();
      await _pumpFailed(tester);

      expect(tester.takeException(), isNull);
      expect(_failedMessage, findsOneWidget);
      expect(find.text(longCaption), findsOneWidget);
      expect(_next, findsOneWidget);
    });

    testWidgets('a video without a playable URL fails at once, with nothing '
        'to retry', (tester) async {
      final controllers = _Controllers();
      final skipped = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(downloadUrl: null),
            onSkipUnplayable: skipped.add,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 5));

      expect(controllers.created, isEmpty);
      expect(_spinner, findsNothing);
      expect(_failedMessage, findsOneWidget);
      expect(find.text(_caption), findsOneWidget);
      expect(_tryAgain, findsNothing);

      await tester.tap(_next);
      expect(skipped, ['clip-1']);
    });

    testWidgets('an init timeout retries once, then fails', (tester) async {
      final controllers = _Controllers();
      final analytics = _RecordingAnalytics();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(textBody: null),
            analytics: analytics,
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      await tester.pump(
        HumorContentPlayer.videoInitTimeout - const Duration(seconds: 1),
      );
      expect(_spinner, findsOneWidget);
      expect(controllers.created, hasLength(1));

      await tester.pump(const Duration(seconds: 1));
      expect(controllers.created.first.disposed, isTrue);
      await _pumpRetry(tester);
      expect(controllers.created, hasLength(2));
      expect(_spinner, findsOneWidget);

      await tester.pump(HumorContentPlayer.videoInitTimeout);
      await _pumpFailed(tester);

      expect(_spinner, findsNothing);
      expect(_failedMessage, findsOneWidget);
      expect(controllers.created.last.disposed, isTrue);
      expect(
        analytics
            .named(AnalyticsEvents.humorMediaFailed)
            .map((p) => (p!['reason'], p['attempt'])),
        [('timeout', 1), ('timeout', 2)],
      );
    });

    testWidgets('a zero-size video retries, then fails instead of a blank '
        'black card', (tester) async {
      final controllers = _Controllers(size: Size.zero);
      final analytics = _RecordingAnalytics();
      final errors = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            onMediaError: errors.add,
            analytics: analytics,
            videoControllerFactory: controllers.call,
          ),
        ),
      );

      controllers.created.single.completeInit();
      await _pumpRetry(tester);
      expect(find.byType(VideoPlayer), findsNothing);
      controllers.created.last.completeInit();
      await _pumpFailed(tester);

      expect(find.byType(VideoPlayer), findsNothing);
      expect(_spinner, findsNothing);
      expect(_failedMessage, findsOneWidget);
      expect(controllers.created.every((c) => c.disposed), isTrue);
      expect(errors, ['clip-1']);
      expect(
        analytics
            .named(AnalyticsEvents.humorMediaFailed)
            .map((p) => p!['reason']),
        ['zero_size', 'zero_size'],
      );
    });

    testWidgets('a clip whose position stops advancing is a stall: retried '
        'once, then failed', (tester) async {
      final controllers = _Controllers();
      final analytics = _RecordingAnalytics();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            analytics: analytics,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      final first = controllers.created.single..completeInit();
      await tester.pump();
      expect(_boundController(tester), same(first));

      // Healthy playback keeps the watchdog quiet well past its timeout.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
        first.advance(const Duration(seconds: 1));
      }
      expect(_boundController(tester), same(first));
      expect(controllers.created, hasLength(1));

      // Frozen: no position change for the stall timeout.
      await tester.pump(
        HumorContentPlayer.playbackStallTimeout - const Duration(seconds: 1),
      );
      expect(_boundController(tester), same(first));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(first.disposed, isTrue);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(_spinner, findsOneWidget, reason: 'silent retry, not a failure');
      _expectNoFailure();

      await _pumpRetry(tester);
      final second = controllers.created.last..completeInit();
      await tester.pump();
      expect(_boundController(tester), same(second));

      await tester.pump(HumorContentPlayer.playbackStallTimeout);
      await _pumpFailed(tester);

      expect(second.disposed, isTrue);
      expect(_spinner, findsNothing);
      expect(_failedMessage, findsOneWidget);
      expect(controllers.created, hasLength(2));
      expect(
        analytics
            .named(AnalyticsEvents.humorMediaFailed)
            .map((p) => (p!['reason'], p['attempt'])),
        [('stall', 1), ('stall', 2)],
      );
    });

    testWidgets('Try again resets the budget exactly once', (tester) async {
      final controllers = _Controllers();
      final analytics = _RecordingAnalytics();
      final errors = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            onMediaError: errors.add,
            onSkipUnplayable: (_) {},
            analytics: analytics,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      controllers.created.single.failInit();
      await _pumpRetry(tester);
      controllers.created.last.failInit();
      await _pumpFailed(tester);
      expect(_tryAgain, findsOneWidget);

      await tester.tap(_tryAgain);
      await tester.pump();
      expect(controllers.created, hasLength(3));
      expect(_spinner, findsOneWidget);
      expect(_failedMessage, findsNothing);

      // The manual attempt gets its own silent retry...
      controllers.created.last.failInit();
      await _pumpRetry(tester);
      expect(controllers.created, hasLength(4));
      controllers.created.last.failInit();
      await _pumpFailed(tester);

      // ...and then it is over: only Next is left.
      expect(_failedMessage, findsOneWidget);
      expect(_tryAgain, findsNothing);
      expect(_next, findsOneWidget);
      expect(_spinner, findsNothing);
      expect(errors, ['clip-1'], reason: 'reported once per appearance');
      expect(
        analytics.named(AnalyticsEvents.humorMediaRetry).map((p) => p!['kind']),
        ['auto', 'manual', 'auto'],
      );

      await tester.pump(const Duration(minutes: 1));
      expect(controllers.created, hasLength(4));
    });

    testWidgets('a manual retry that succeeds plays the clip', (tester) async {
      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      controllers.created.single.failInit();
      await _pumpRetry(tester);
      controllers.created.last.failInit();
      await _pumpFailed(tester);

      await tester.tap(_tryAgain);
      await tester.pump();
      final clip = controllers.created.last..completeInit();
      await tester.pump();

      expect(_boundController(tester), same(clip));
      expect(clip.playCalls, 1);
      _expectNoFailure();
    });

    testWidgets('Next hands the contentId to onSkipUnplayable', (tester) async {
      final controllers = _Controllers();
      final skipped = <String>[];
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(contentId: 'broken-clip'),
            onSkipUnplayable: skipped.add,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      controllers.created.single.failInit();
      await _pumpRetry(tester);
      controllers.created.last.failInit();
      await _pumpFailed(tester);

      await tester.tap(_next);
      await tester.pump();

      expect(skipped, ['broken-clip']);
    });

    testWidgets('a clip that breaks while playing is retried, then fails', (
      tester,
    ) async {
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
      expect(clip.disposed, isTrue);
      expect(_spinner, findsOneWidget);
      expect(errors, isEmpty);

      await _pumpRetry(tester);
      final second = controllers.created.last..completeInit();
      await tester.pump();
      second.value = second.value.copyWith(errorDescription: 'decoder died');
      await _pumpFailed(tester);

      expect(_spinner, findsNothing);
      expect(_failedMessage, findsOneWidget);
      expect(second.disposed, isTrue);
      expect(errors, ['clip-1']);
    });

    testWidgets('landscape video is letterboxed, portrait video fills the '
        'card', (tester) async {
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
      expect(
        tester.widget<FittedBox>(find.byType(FittedBox)).fit,
        BoxFit.cover,
      );
    });
  });

  group('lifecycle', () {
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

    testWidgets('a content change during the retry pause starts only the new '
        'clip', (tester) async {
      final controllers = _Controllers();
      Widget player(HumorContent content) => _wrap(
        HumorContentPlayer(
          content: content,
          videoControllerFactory: controllers.call,
        ),
      );

      await tester.pumpWidget(player(_video(contentId: 'first')));
      controllers.created.single.failInit();
      await tester.pump();

      await tester.pumpWidget(
        player(
          _video(
            contentId: 'second',
            downloadUrl: 'https://cdn.example.test/humor/second.mp4',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 5));

      expect(controllers.created.map((c) => c.dataSource), [
        _clipUrl,
        'https://cdn.example.test/humor/second.mp4',
      ]);
    });

    testWidgets('replay seeks the loaded clip; an off-screen card pauses, '
        'ignores replays and is never judged stalled', (tester) async {
      final controllers = _Controllers();
      Widget player({required bool isActive, required int replayToken}) =>
          _wrap(
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

      // Paused off screen, a frozen position is expected, not a stall.
      await tester.pump(HumorContentPlayer.playbackStallTimeout * 3);
      expect(_boundController(tester), same(clip));
      expect(clip.disposed, isFalse);

      // Back on screen: it resumes rather than reloading.
      await tester.pumpWidget(player(isActive: true, replayToken: 2));
      await tester.pump();
      expect(clip.playCalls, 3);
      expect(controllers.created, hasLength(1));
    });

    testWidgets('going to the background pauses; coming back resumes only '
        'the active card', (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      final clip = controllers.created.single..completeInit();
      await tester.pump();
      expect(clip.playCalls, 1);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(clip.pauseCalls, 1);
      expect(clip.value.isPlaying, isFalse);

      // In the background, no progress is not a stall.
      await tester.pump(HumorContentPlayer.playbackStallTimeout * 3);
      expect(_boundController(tester), same(clip));
      expect(controllers.created, hasLength(1));

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(clip.playCalls, 2);
      expect(clip.value.isPlaying, isTrue);
    });

    testWidgets('an inactive card stays paused when the app comes back', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final controllers = _Controllers();
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _video(),
            isActive: false,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      final clip = controllers.created.single..completeInit();
      await tester.pump();
      expect(clip.playCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(clip.playCalls, 0);
    });

    testWidgets('dispose releases the bound controller and its watchdog', (
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
      expect(controllers.created.single.disposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(controllers.created.single.disposed, isTrue);
      // flutter_test fails the test if the stall watchdog were still pending.
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

    testWidgets('dispose during the retry pause starts nothing new', (
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
      controllers.created.single.failInit();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));

      expect(controllers.created, hasLength(1));
    });
  });
}
