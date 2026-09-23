import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/pkce.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/authentication/data/services/spotify_pending_store.dart';
import 'package:url_launcher/url_launcher.dart';

const _config = AppConfig(environment: AppEnvironment.development);

/// Records every backend exchange so a test can assert which callable ran and
/// how many times a single authorization code reached it.
class _RecordingExchange {
  _RecordingExchange({this.response = const <String, dynamic>{}, this.error});

  final Map<String, dynamic> response;
  final Object? error;
  final calls = <({String name, Map<String, dynamic> data})>[];

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    calls.add((name: name, data: data));
    // Yield so a second delivery of the same callback has a real chance to
    // race this one, the way two link sources would on a cold start.
    await Future<void>.delayed(Duration.zero);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return response;
  }

  List<String> get names => calls.map((call) => call.name).toList();
}

typedef _Harness = ({
  SpotifyAuthService service,
  _RecordingExchange exchange,
  MemorySpotifyPendingStore store,
});

/// Builds a service whose only callback source is [links], with a pending PKCE
/// session already stored — the state a resumed process picks up from.
_Harness _serviceWithPending({
  required StreamController<Uri> links,
  required SpotifyOAuthPurpose purpose,
  String state = 'state-1',
  Map<String, dynamic> response = const <String, dynamic>{},
  Object? error,
}) {
  final store = MemorySpotifyPendingStore();
  unawaited(
    store.save(
      SpotifyPendingAuth(
        state: state,
        verifier: 'verifier-on-device',
        linkToCurrentUser: purpose == SpotifyOAuthPurpose.musicLink,
        purpose: purpose,
      ),
    ),
  );
  final exchange = _RecordingExchange(response: response, error: error);
  final service = SpotifyAuthService(
    config: _config,
    callbackLinks: links.stream,
    exchange: exchange.call,
    pendingStore: store,
    launch: (uri, {mode = LaunchMode.platformDefault}) async => true,
  );
  return (service: service, exchange: exchange, store: store);
}

/// Lets the link stream deliver and the exchange future settle.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('PKCE verifier stays on device and challenge is S256 shaped', () {
    final pair = PkcePair.generate();
    expect(pair.verifier, isNotEmpty);
    expect(pair.challenge, isNotEmpty);
    expect(pair.verifier.contains('='), isFalse);
    expect(pair.challenge.contains('='), isFalse);
    expect(pair.verifier, isNot(pair.challenge));
  });

  test('Spotify callback URIs are recognized', () {
    expect(
      SpotifyAuthService.isSpotifyCallback(
        Uri.parse('mevora://auth/spotify?code=abc&state=1'),
      ),
      isTrue,
    );
    expect(
      SpotifyAuthService.isSpotifyCallback(
        Uri.parse('https://mevora.app/auth/spotify?code=abc'),
      ),
      isTrue,
    );
    expect(
      SpotifyAuthService.isSpotifyCallback(
        Uri.parse('https://evil.example/auth'),
      ),
      isFalse,
    );
    expect(
      SpotifyAuthService.musicScopes,
      'user-top-read user-read-recently-played playlist-read-private',
    );
    expect(SpotifyAuthService.musicScopes.contains('streaming'), isFalse);
    expect(SpotifyAuthService.loginScopes.contains('streaming'), isFalse);
  });

  test('pending PKCE store round-trips without a client secret', () async {
    final store = MemorySpotifyPendingStore();
    await store.save(
      const SpotifyPendingAuth(
        state: 'state-1',
        verifier: 'verifier-on-device',
        linkToCurrentUser: false,
      ),
    );
    final pending = await store.read();
    expect(pending?.verifier, 'verifier-on-device');
    await store.clear();
    expect(await store.read(), isNull);
  });

  group('OAuth scopes stay least-privilege', () {
    test('login asks for identity only', () {
      expect(SpotifyAuthService.loginScopes, 'user-read-private');
      for (final scope in const [
        'user-top-read',
        'user-read-recently-played',
        'playlist-read-private',
      ]) {
        expect(
          SpotifyAuthService.loginScopes.contains(scope),
          isFalse,
          reason: 'login must not carry the music scope $scope',
        );
      }
    });

    test('music link asks for taste only, never playback or modification', () {
      for (final scope in const [
        'streaming',
        'app-remote-control',
        'user-modify-playback-state',
        'playlist-modify-public',
        'playlist-modify-private',
        'user-library-modify',
        'ugc-image-upload',
      ]) {
        expect(
          SpotifyAuthService.musicScopes.contains(scope),
          isFalse,
          reason: 'music link must not request $scope',
        );
      }
    });
  });

  group('OAuth callback contract', () {
    test('login purpose exchanges through spotifyCompleteAuth', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final harness = _serviceWithPending(
        links: links,
        purpose: SpotifyOAuthPurpose.login,
        response: const {'customToken': null, 'alreadyLinked': false},
      );
      addTearDown(harness.service.dispose);

      links.add(Uri.parse('mevora://auth/spotify?code=code-1&state=state-1'));
      await _settle();

      expect(harness.exchange.names, ['spotifyCompleteAuth']);
      expect(
        harness.exchange.calls.single.data['codeVerifier'],
        'verifier-on-device',
      );
    });

    test('music purpose exchanges through spotifyLinkMusic', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final harness = _serviceWithPending(
        links: links,
        purpose: SpotifyOAuthPurpose.musicLink,
      );
      addTearDown(harness.service.dispose);

      links.add(Uri.parse('mevora://auth/spotify?code=code-1&state=state-1'));
      await _settle();

      expect(harness.exchange.names, ['spotifyLinkMusic']);
    });

    test('an unrelated deep link is ignored', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final harness = _serviceWithPending(
        links: links,
        purpose: SpotifyOAuthPurpose.musicLink,
      );
      addTearDown(harness.service.dispose);

      links.add(Uri.parse('mevora://match/42?code=code-1&state=state-1'));
      links.add(
        Uri.parse('https://evil.example/auth/spotify?code=c&state=state-1'),
      );
      await _settle();

      expect(harness.exchange.calls, isEmpty);
      expect(await harness.store.read(), isNotNull, reason: 'pending survives');
    });

    test(
      'a forged state never reaches the backend and clears the session',
      () async {
        final links = StreamController<Uri>();
        addTearDown(links.close);
        final harness = _serviceWithPending(
          links: links,
          purpose: SpotifyOAuthPurpose.musicLink,
        );
        addTearDown(harness.service.dispose);

        links.add(Uri.parse('mevora://auth/spotify?code=code-1&state=attacker'));
        await _settle();

        expect(harness.exchange.calls, isEmpty);
        expect(await harness.store.read(), isNull);
      },
    );

    test('a callback without a code is rejected', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final harness = _serviceWithPending(
        links: links,
        purpose: SpotifyOAuthPurpose.musicLink,
      );
      addTearDown(harness.service.dispose);

      links.add(Uri.parse('mevora://auth/spotify?state=state-1'));
      await _settle();

      expect(harness.exchange.calls, isEmpty);
      expect(await harness.store.read(), isNull);
    });

    test(
      'a provider error clears the pending session without exchanging',
      () async {
        final links = StreamController<Uri>();
        addTearDown(links.close);
        final harness = _serviceWithPending(
          links: links,
          purpose: SpotifyOAuthPurpose.musicLink,
        );
        addTearDown(harness.service.dispose);

        links.add(
          Uri.parse('mevora://auth/spotify?error=access_denied&state=state-1'),
        );
        await _settle();

        expect(harness.exchange.calls, isEmpty);
        expect(await harness.store.read(), isNull);
      },
    );

    test('a successful exchange clears the pending session', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final harness = _serviceWithPending(
        links: links,
        purpose: SpotifyOAuthPurpose.musicLink,
      );
      addTearDown(harness.service.dispose);

      links.add(Uri.parse('mevora://auth/spotify?code=code-1&state=state-1'));
      await _settle();

      expect(harness.exchange.names, ['spotifyLinkMusic']);
      expect(await harness.store.read(), isNull);
    });

    test('a failed exchange clears the pending session', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final harness = _serviceWithPending(
        links: links,
        purpose: SpotifyOAuthPurpose.musicLink,
        error: const AuthException('boom', kind: AuthErrorKind.oauth),
      );
      addTearDown(harness.service.dispose);

      links.add(Uri.parse('mevora://auth/spotify?code=code-1&state=state-1'));
      await _settle();

      expect(harness.exchange.names, ['spotifyLinkMusic']);
      expect(await harness.store.read(), isNull);
    });

    test(
      'a redelivered callback exchanges the one-time code exactly once',
      () async {
        final links = StreamController<Uri>();
        addTearDown(links.close);
        final harness = _serviceWithPending(
          links: links,
          purpose: SpotifyOAuthPurpose.musicLink,
        );
        addTearDown(harness.service.dispose);

        // A cold start used to reach the service twice — once through
        // uriLinkStream and once through handleInitialUri(). A Spotify
        // authorization code is single-use, so the second exchange would fail
        // and surface as a false OAuth error on a link that actually worked.
        final callback = Uri.parse(
          'mevora://auth/spotify?code=code-1&state=state-1',
        );
        links.add(callback);
        links.add(callback);
        await _settle();

        expect(harness.exchange.names, ['spotifyLinkMusic']);
      },
    );

    test(
      'a replayed callback after completion cannot exchange again',
      () async {
        final links = StreamController<Uri>();
        addTearDown(links.close);
        final harness = _serviceWithPending(
          links: links,
          purpose: SpotifyOAuthPurpose.musicLink,
        );
        addTearDown(harness.service.dispose);

        final callback = Uri.parse(
          'mevora://auth/spotify?code=code-1&state=state-1',
        );
        links.add(callback);
        await _settle();
        links.add(callback);
        await _settle();

        expect(harness.exchange.names, ['spotifyLinkMusic']);
      },
    );
  });
}
