import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/data/pkce.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/authentication/data/services/spotify_pending_store.dart';

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
      SpotifyAuthService.isSpotifyCallback(Uri.parse('https://evil.example/auth')),
      isFalse,
    );
    expect(
      SpotifyAuthService.musicScopes,
      'user-top-read user-read-recently-played playlist-read-private',
    );
    expect(SpotifyAuthService.musicScopes.contains('streaming'), isFalse);
    expect(SpotifyAuthService.loginScopes.contains('streaming'), isFalse);
  });

  test('Spotify OAuth callback is not a GoRouter app page path', () {
    final callback = Uri.parse('mevora://auth/spotify?code=abc&state=1');
    expect(callback.path, '/spotify');
    expect(callback.path, isNot(AppRoutes.music));
    expect(callback.path, isNot(AppRoutes.login));
    expect(SpotifyAuthService.isSpotifyCallback(callback), isTrue);
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
}
