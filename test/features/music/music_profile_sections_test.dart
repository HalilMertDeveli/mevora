import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/data/services/spotify_auth_service.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';

void main() {
  group('the music connection asks for what it needs and nothing more', () {
    test('it can read the artists the member follows', () {
      expect(SpotifyAuthService.musicScopes, contains('user-follow-read'));
    });

    test('it keeps the scopes the private model still uses', () {
      for (final scope in [
        'user-top-read',
        'user-read-recently-played',
        'playlist-read-private',
      ]) {
        expect(SpotifyAuthService.musicScopes, contains(scope));
      }
    });

    test('it asks for nothing to do with playback or writing', () {
      for (final scope in [
        'streaming',
        'playlist-modify',
        'playlist-read-collaborative',
        'user-library-modify',
        'user-follow-modify',
      ]) {
        expect(
          SpotifyAuthService.musicScopes.contains(scope),
          isFalse,
          reason: '$scope is not ours to ask for',
        );
      }
    });

    test('signing in stays identity-only', () {
      expect(SpotifyAuthService.loginScopes, 'user-read-private');
      expect(
        SpotifyAuthService.loginScopes.contains('user-follow-read'),
        isFalse,
        reason: 'following is a music permission, not a sign-in one',
      );
    });
  });

  group('what a member may publish', () {
    const topOne = MusicArtist(id: 'a1', name: 'Top One');
    const followedOne = MusicArtist(id: 'f1', name: 'Followed One');

    test('a followed artist joins the top ones', () {
      const profile = MusicProfile(
        connected: true,
        topArtists: [topOne],
        followedArtists: [followedOne],
      );
      expect(
        profile.selectableArtists.map((a) => a.id),
        ['a1', 'f1'],
        reason: 'following is a deliberate choice, so it counts',
      );
    });

    test('an artist in both lists is offered once', () {
      const profile = MusicProfile(
        connected: true,
        topArtists: [topOne],
        followedArtists: [topOne, followedOne],
      );
      expect(profile.selectableArtists.map((a) => a.id), ['a1', 'f1']);
    });

    test('with nothing followed it is just the top artists', () {
      const profile = MusicProfile(connected: true, topArtists: [topOne]);
      expect(profile.selectableArtists, [topOne]);
    });
  });

  group('a connection made before we asked to read follows', () {
    test('is offered a way to fix it', () {
      const older = MusicProfile(connected: true);
      expect(older.canReconnectForFollowedArtists, isTrue);
    });

    test('a current connection is not nagged', () {
      const current = MusicProfile(connected: true, followScopeGranted: true);
      expect(current.canReconnectForFollowedArtists, isFalse);
    });

    test('a disconnected member is not asked to reconnect for follows', () {
      expect(
        MusicProfile.disconnected.canReconnectForFollowedArtists,
        isFalse,
        reason: 'they have no Spotify connection to re-grant anything on',
      );
    });
  });

  group('the profile limits are the same on both sides', () {
    test('five top items, ten follows', () {
      // Mirrors PROFILE_TOP_LIMIT and FOLLOWED_ARTIST_LIMIT in
      // functions/src/spotifyMusic.ts.
      expect(profileTopItemLimit, 5);
      expect(followedArtistLimit, 10);
    });
  });

  group('playlists stay on the owner\'s own screen', () {
    test('a playlist carries only what the screen shows', () {
      const playlist = MusicPlaylist(
        id: 'p1',
        name: 'Late night mix',
        trackCount: 42,
      );
      expect(playlist.name, 'Late night mix');
      expect(playlist.trackCount, 42);
    });

    test('they are part of the owner profile, never the public card', () {
      const profile = MusicProfile(
        connected: true,
        playlists: [MusicPlaylist(id: 'p1', name: 'Late night mix')],
      );
      expect(profile.playlists, hasLength(1));
      expect(
        profile.publicProfile.artists,
        isEmpty,
        reason: 'nothing about playlists belongs on a dating profile',
      );
    });
  });
}
