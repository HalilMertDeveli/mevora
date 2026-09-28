import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_content_player.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

/// GIPHY GIFs arrive as "meme" cards whose media is an animated WebP/GIF.
/// They must render through Flutter's image pipeline (poster while loading,
/// then the looping animation), fail into "Try again"/"Next", never spin
/// forever, and never touch a video player.

final _en = lookupAppLocalizations(const Locale('en'));

const _caption = 'Komik Tepki';

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

/// A GIPHY GIF card as the backend now serves it.
HumorContent _gifCard(String id, {String? textBody = _caption}) {
  return HumorContent(
    contentId: 'ext_giphy_$id',
    type: HumorContentType.meme,
    language: 'tr',
    category: HumorCategory.meme,
    textBody: textBody,
    downloadUrl: _webpUrl(id),
    thumbUrl: _posterUrl(id),
    aspectRatio: 480 / 270,
    attribution: const HumorContentAttribution(
      provider: 'giphy',
      username: 'gainmedya',
      verified: true,
    ),
  );
}

String _webpUrl(String id) => 'https://media1.giphy.com/media/$id/giphy.webp';
String _posterUrl(String id) => 'https://media1.giphy.com/media/$id/200_s.gif';

/// A 1×1 two-frame looping GIF: a real animated image for the decoder.
final Uint8List _animatedGif = Uint8List.fromList(<int>[
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
  0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // 1×1, 2-colour global table
  0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
  // NETSCAPE2.0: loop forever.
  0x21, 0xFF, 0x0B, 0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32,
  0x2E, 0x30, 0x03, 0x01, 0x00, 0x00, 0x00,
  // Frame 1 (100 ms).
  0x21, 0xF9, 0x04, 0x04, 0x0A, 0x00, 0x00, 0x00,
  0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0x02, 0x02, 0x44, 0x01, 0x00,
  // Frame 2 (100 ms).
  0x21, 0xF9, 0x04, 0x04, 0x0A, 0x00, 0x00, 0x00,
  0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
  0x02, 0x02, 0x4C, 0x01, 0x00,
  0x3B,
]);

/// How the fake network answers one URL.
class _Reply {
  _Reply.bytes(Uint8List bytes)
    : _response = Future.value(_Response(200, bytes));
  _Reply.status(int status)
    : _response = Future.value(_Response(status, Uint8List(0)));

  /// Answers only when [later] completes — or never.
  _Reply.later(Completer<_Response> later) : _response = later.future;

  final Future<_Response> _response;
}

class _HttpClient implements HttpClient {
  _HttpClient(this.replies);

  final Map<String, _Reply> replies;
  final requested = <String>[];

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url.toString());
    final reply = replies[url.toString()] ?? _Reply.status(404);
    return _Request(reply._response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this._response);

  final Future<_Response> _response;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.bytes);

  @override
  final int statusCode;
  final Uint8List bytes;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _Headers();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

/// Every video controller the player asks for.
class _Controllers {
  final created = <Uri>[];

  VideoPlayerController call(Uri uri) {
    created.add(uri);
    return VideoPlayerController.networkUrl(uri);
  }
}

/// Runs [body] with every NetworkImage served by [client].
Future<void> _withNetwork(
  _HttpClient client,
  Future<void> Function() body,
) async {
  debugNetworkImageHttpClientProvider = () => client;
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

Finder _imageOf(String url) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      (widget.image as NetworkImage).url == url,
);

Finder get _spinner => find.byType(CircularProgressIndicator);
Finder get _failed => find.text(_en.humorMediaUnavailable);
Finder get _tryAgain => find.widgetWithText(OutlinedButton, _en.humorTryAgain);
Finder get _next => find.widgetWithText(FilledButton, _en.humorMediaNext);

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Lets the real image decoder run (it lives outside the fake clock).
Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The frame the main (animated) image currently paints, if any.
RawImage? _paintedMain(WidgetTester tester, String url) {
  final raw = find.descendant(
    of: _imageOf(url),
    matching: find.byType(RawImage),
  );
  if (raw.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<RawImage>(raw);
}

void main() {
  testWidgets('a GIPHY GIF card shows its poster while the animated image '
      'loads, then the image, and never creates a video controller', (
    tester,
  ) async {
    const id = 'gifLoad01';
    final later = Completer<_Response>();
    final client = _HttpClient({
      _webpUrl(id): _Reply.later(later),
      _posterUrl(id): _Reply.bytes(_animatedGif),
    });
    final controllers = _Controllers();

    await _withNetwork(client, () async {
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _gifCard(id),
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      await tester.pump();

      // Loading: the item's own still poster, a spinner, the caption once.
      expect(_imageOf(_posterUrl(id)), findsOneWidget);
      expect(_imageOf(_webpUrl(id)), findsOneWidget);
      expect(_spinner, findsOneWidget);
      expect(find.text(_caption), findsOneWidget);
      expect(find.text('GIPHY · @gainmedya'), findsOneWidget);
      expect(find.text(_en.humorCategoryMeme), findsOneWidget);
      expect(_failed, findsNothing);

      // The animated image arrives and is decoded.
      later.complete(_Response(200, _animatedGif));
      await _decode(tester);

      expect(_paintedMain(tester, _webpUrl(id))?.image, isNotNull);
      expect(_imageOf(_posterUrl(id)), findsNothing, reason: 'poster gone');
      expect(_spinner, findsNothing);
      expect(find.text(_caption), findsOneWidget);
      expect(find.text('GIPHY · @gainmedya'), findsOneWidget);
      expect(_failed, findsNothing);

      // Well past the load timeout: a shown image is never judged failed.
      await tester.pump(HumorContentPlayer.imageLoadTimeout * 2);
      expect(_failed, findsNothing);

      expect(controllers.created, isEmpty);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(HumorContentPlayer.isVideoContent(_gifCard(id)), isFalse);
      expect(HumorContentPlayer.stillUrlFor(_gifCard(id)), _webpUrl(id));

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the animated image keeps running frames (it loops)', (
    tester,
  ) async {
    const id = 'gifLoop01';
    final client = _HttpClient({_webpUrl(id): _Reply.bytes(_animatedGif)});

    await _withNetwork(client, () async {
      await tester.pumpWidget(
        _wrap(HumorContentPlayer(content: _gifCard(id, textBody: null))),
      );
      await _decode(tester);
      final seen = <Object?>{_paintedMain(tester, _webpUrl(id))?.image};
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
        await _decode(tester);
        seen.add(_paintedMain(tester, _webpUrl(id))?.image);
      }
      seen.remove(null);
      expect(seen.length, greaterThan(1), reason: 'more than one frame shown');

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('an animated image that fails shows the failed UI with Try '
      'again and Next; Next skips the item', (tester) async {
    const id = 'gifFail01';
    final client = _HttpClient({
      _webpUrl(id): _Reply.status(404),
      _posterUrl(id): _Reply.bytes(_animatedGif),
    });
    final errors = <String>[];
    final skipped = <String>[];
    final analytics = _RecordingAnalytics();
    final controllers = _Controllers();

    await _withNetwork(client, () async {
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _gifCard(id),
            onMediaError: errors.add,
            onSkipUnplayable: skipped.add,
            analytics: analytics,
            videoControllerFactory: controllers.call,
          ),
        ),
      );
      await _pumpUntilFound(tester, _failed);
      await tester.pump();

      expect(_failed, findsOneWidget);
      expect(_tryAgain, findsOneWidget);
      expect(_next, findsOneWidget);
      expect(_spinner, findsNothing);
      expect(find.text(_caption), findsOneWidget, reason: 'text shown once');
      expect(_imageOf(_posterUrl(id)), findsOneWidget, reason: 'dim poster');
      expect(errors, ['ext_giphy_$id']);
      expect(analytics.named(AnalyticsEvents.humorMediaFailed).single, {
        'content_id': 'ext_giphy_$id',
        'media': 'image',
        'reason': 'error',
        'attempt': 1,
      });

      await tester.tap(_next);
      expect(skipped, ['ext_giphy_$id']);

      // Try again fetches once more; failing again leaves only Next.
      final before = client.requested.where((u) => u == _webpUrl(id)).length;
      await tester.tap(_tryAgain);
      await tester.pump();
      await _pumpUntilFound(tester, _failed);
      await tester.pump();
      expect(
        client.requested.where((u) => u == _webpUrl(id)).length,
        before + 1,
      );
      expect(_failed, findsOneWidget);
      expect(_tryAgain, findsNothing, reason: 'Try again is offered once');
      expect(_next, findsOneWidget);
      expect(
        analytics.named(AnalyticsEvents.humorMediaRetry).single?['kind'],
        'manual',
      );
      expect(errors, hasLength(1), reason: 'reported once per item');
      expect(controllers.created, isEmpty);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('an animated image that never answers times out into the '
      'failed UI instead of spinning forever', (tester) async {
    const id = 'gifHang01';
    final client = _HttpClient({
      _webpUrl(id): _Reply.later(Completer<_Response>()),
      _posterUrl(id): _Reply.bytes(_animatedGif),
    });
    final errors = <String>[];
    final analytics = _RecordingAnalytics();

    await _withNetwork(client, () async {
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(
            content: _gifCard(id),
            onMediaError: errors.add,
            onSkipUnplayable: (_) {},
            analytics: analytics,
          ),
        ),
      );
      await tester.pump();
      expect(_spinner, findsOneWidget);

      await tester.pump(
        HumorContentPlayer.imageLoadTimeout - const Duration(seconds: 1),
      );
      expect(_failed, findsNothing, reason: 'still within the timeout');
      expect(_spinner, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(_failed, findsOneWidget);
      expect(_spinner, findsNothing);
      expect(_tryAgain, findsOneWidget);
      expect(_next, findsOneWidget);
      expect(errors, ['ext_giphy_$id']);
      expect(
        analytics.named(AnalyticsEvents.humorMediaFailed).single?['reason'],
        'timeout',
      );

      // Try again: loading (poster + spinner), bounded again.
      await tester.tap(_tryAgain);
      await tester.pump();
      expect(_failed, findsNothing);
      expect(_spinner, findsOneWidget);
      expect(_imageOf(_posterUrl(id)), findsOneWidget);
      await tester.pump(HumorContentPlayer.imageLoadTimeout);
      await tester.pump();
      expect(_failed, findsOneWidget);
      expect(_tryAgain, findsNothing);
      expect(_next, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('disposing a loading image card leaves no timer behind', (
    tester,
  ) async {
    const id = 'gifDispose01';
    final client = _HttpClient({
      _webpUrl(id): _Reply.later(Completer<_Response>()),
    });
    final errors = <String>[];

    await _withNetwork(client, () async {
      await tester.pumpWidget(
        _wrap(
          HumorContentPlayer(content: _gifCard(id), onMediaError: errors.add),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(HumorContentPlayer.imageLoadTimeout * 2);
      expect(errors, isEmpty);
    });
  });
}
