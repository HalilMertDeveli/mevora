import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/presentation/controllers/public_music_controller.dart';
import 'package:mevora/features/music/presentation/pages/public_music_selection_page.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_taste_section.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
  );
}

MusicProfile _connectedProfile({
  int artistCount = 5,
  int trackCount = 5,
  PublicMusicProfile published = PublicMusicProfile.hidden,
}) {
  return MusicProfile(
    connected: true,
    spotifyUserId: 'spotify-user-1',
    displayName: 'Listener',
    topArtists: List.generate(
      artistCount,
      (i) => MusicArtist(id: 'a$i', name: 'Artist $i', genres: const ['indie']),
    ),
    topTracks: List.generate(
      trackCount,
      (i) => MusicTrack(id: 't$i', name: 'Track $i', artist: 'Band $i'),
    ),
    genres: const [GenreShare(name: 'indie', percent: 60)],
    taste: const MusicTasteSnapshot(trackIds: ['t0'], artistIds: ['a0']),
    publicProfile: published,
  );
}

({PublicMusicController controller, MockMusicDataSource source}) _harness({
  MusicProfile? profile,
}) {
  final resolved = profile ?? _connectedProfile();
  final source = MockMusicDataSource(connectedProfile: resolved);
  final repository = MusicRepositoryImpl(dataSource: source);
  // Put the mock into its connected state so publishing is possible.
  return (
    controller: PublicMusicController(
      repository: repository,
      profile: resolved,
    ),
    source: source,
  );
}

void main() {
  group('selection limits', () {
    test('accepts zero, one and three artists', () {
      final harness = _harness();
      final controller = harness.controller;
      expect(controller.state.selectedArtistIds, isEmpty);

      controller.toggleArtist('a0');
      expect(controller.state.selectedArtistIds.length, 1);

      controller.toggleArtist('a1');
      controller.toggleArtist('a2');
      expect(controller.state.selectedArtistIds.length, maxPublicMusicArtists);
    });

    test('refuses a fourth artist instead of swapping one out', () {
      final controller = _harness().controller;
      for (final id in ['a0', 'a1', 'a2']) {
        controller.toggleArtist(id);
      }
      controller.toggleArtist('a3');

      expect(controller.state.selectedArtistIds.length, maxPublicMusicArtists);
      expect(controller.state.selectedArtistIds.contains('a3'), isFalse);
      expect(controller.state.selectedArtistIds.contains('a0'), isTrue);
    });

    test('refuses a fourth track', () {
      final controller = _harness().controller;
      for (final id in ['t0', 't1', 't2']) {
        controller.toggleTrack(id);
      }
      controller.toggleTrack('t3');

      expect(controller.state.selectedTrackIds.length, maxPublicMusicTracks);
      expect(controller.state.selectedTrackIds.contains('t3'), isFalse);
    });

    test('deselecting frees a slot again', () {
      final controller = _harness().controller;
      for (final id in ['a0', 'a1', 'a2']) {
        controller.toggleArtist(id);
      }
      controller.toggleArtist('a0');
      controller.toggleArtist('a3');

      expect(controller.state.selectedArtistIds, {'a1', 'a2', 'a3'});
    });

    test('toggling the same artist twice is idempotent, not a duplicate', () {
      final controller = _harness().controller;
      controller.toggleArtist('a0');
      controller.toggleArtist('a0');
      expect(controller.state.selectedArtistIds, isEmpty);
    });

    test('an already-published selection reopens pre-ticked', () {
      const published = PublicMusicProfile(
        enabled: true,
        artists: [PublicMusicArtist(id: 'a1', name: 'Artist 1')],
        tracks: [PublicMusicTrack(id: 't2', name: 'Track 2')],
      );
      final controller = _harness(
        profile: _connectedProfile(published: published),
      ).controller;

      expect(controller.state.selectedArtistIds, {'a1'});
      expect(controller.state.selectedTrackIds, {'t2'});
      expect(controller.state.enabled, isTrue);
    });
  });

  group('publishing', () {
    test('publishes the selection and adopts the server result', () async {
      final harness = _harness();
      await harness.source.connectSpotify();
      final controller = harness.controller;
      controller.toggleArtist('a0');
      controller.toggleTrack('t0');

      final saved = await controller.save();

      expect(saved, isTrue);
      expect(harness.source.publicMusicUpdateCalls, 1);
      expect(controller.state.profile.publicProfile.enabled, isTrue);
      expect(controller.state.profile.publicProfile.artistIds, ['a0']);
      expect(controller.state.phase, PublicMusicPhase.saved);
    });

    test('an unknown artist id is rejected by the backend contract', () async {
      // The mock mirrors the server: only imported items may be published.
      final harness = _harness();
      await harness.source.connectSpotify();
      await expectLater(
        harness.source.updatePublicMusicProfile(
          enabled: true,
          artistIds: const ['taylor-swift-real-id'],
          trackIds: const [],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an unknown track id is rejected', () async {
      final harness = _harness();
      await harness.source.connectSpotify();
      await expectLater(
        harness.source.updatePublicMusicProfile(
          enabled: true,
          artistIds: const [],
          trackIds: const ['not-mine'],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a save failure keeps the member in the editor with an error', () async {
      final harness = _harness();
      await harness.source.connectSpotify();
      harness.source.failPublicMusicUpdate = true;
      harness.controller.toggleArtist('a0');

      final saved = await harness.controller.save();

      expect(saved, isFalse);
      expect(harness.controller.state.phase, PublicMusicPhase.editing);
      expect(harness.controller.state.failure, isNotNull);
    });

    test('hiding the section keeps the selection and the connection', () async {
      final harness = _harness();
      await harness.source.connectSpotify();
      harness.controller.toggleArtist('a0');
      await harness.controller.save();

      harness.controller.setEnabled(false);
      await harness.controller.save();

      expect(harness.controller.state.profile.publicProfile.enabled, isFalse);
      expect(
        harness.controller.state.profile.connected,
        isTrue,
        reason: 'hiding must not disconnect Spotify',
      );
    });
  });

  group('selection UI', () {
    testWidgets('shows the prompt and the running count', (tester) async {
      final controller = _harness().controller;
      await tester.pumpWidget(
        _wrap(PublicMusicSelectionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.publicMusicTitle), findsOneWidget);
      expect(find.text(_en.publicMusicSubtitle), findsOneWidget);
      expect(find.text(_en.publicMusicArtistCount(0, 3)), findsOneWidget);
    });

    testWidgets('a fourth artist chip cannot be tapped', (tester) async {
      final controller = _harness().controller;
      await tester.pumpWidget(
        _wrap(PublicMusicSelectionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      for (final name in ['Artist 0', 'Artist 1', 'Artist 2']) {
        await tester.tap(find.text(name));
        await tester.pump();
      }
      expect(find.text(_en.publicMusicArtistCount(3, 3)), findsOneWidget);
      expect(find.text(_en.publicMusicLimitReached), findsWidgets);

      await tester.ensureVisible(find.text('Artist 3'));
      await tester.pump();
      await tester.tap(find.text('Artist 3'), warnIfMissed: false);
      await tester.pump();

      expect(controller.state.selectedArtistIds.contains('a3'), isFalse);
      expect(find.text(_en.publicMusicArtistCount(3, 3)), findsOneWidget);
    });

    testWidgets('an account with no imported data explains itself', (
      tester,
    ) async {
      final controller = _harness(
        profile: _connectedProfile(artistCount: 0, trackCount: 0),
      ).controller;
      await tester.pumpWidget(
        _wrap(PublicMusicSelectionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Connected with nothing to show is not an error.
      expect(find.text(_en.publicMusicEmpty), findsOneWidget);
      expect(find.text(_en.publicMusicSave), findsNothing);
    });

    testWidgets('works when only one artist and two tracks exist', (
      tester,
    ) async {
      final controller = _harness(
        profile: _connectedProfile(artistCount: 1, trackCount: 2),
      ).controller;
      await tester.pumpWidget(
        _wrap(PublicMusicSelectionPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Artist 0'), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text(_en.publicMusicEmpty), findsNothing);
    });
  });

  group('profile Music Taste section', () {
    testWidgets('renders the published artists, tracks and genres', (
      tester,
    ) async {
      const profile = PublicMusicProfile(
        enabled: true,
        artists: [
          PublicMusicArtist(id: 'a1', name: 'Arctic Monkeys'),
          PublicMusicArtist(id: 'a2', name: 'The Weeknd'),
        ],
        tracks: [PublicMusicTrack(id: 't1', name: '505', artist: 'Arctic Monkeys')],
        genres: ['alternative', 'r&b'],
      );

      await tester.pumpWidget(
        _wrap(const PublicMusicTasteSection(profile: profile)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.profileMusicTasteHeading), findsOneWidget);
      expect(find.text('Arctic Monkeys'), findsWidgets);
      expect(find.text('505'), findsOneWidget);
      expect(find.text('Alternative · R&b'), findsOneWidget);
    });

    testWidgets('renders nothing when hidden by its owner', (tester) async {
      const hidden = PublicMusicProfile(
        enabled: false,
        artists: [PublicMusicArtist(id: 'a1', name: 'Arctic Monkeys')],
      );
      await tester.pumpWidget(
        _wrap(const PublicMusicTasteSection(profile: hidden)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.profileMusicTasteHeading), findsNothing);
      expect(find.text('Arctic Monkeys'), findsNothing);
    });

    testWidgets('renders nothing rather than an empty card', (tester) async {
      const empty = PublicMusicProfile(enabled: true);
      await tester.pumpWidget(
        _wrap(const PublicMusicTasteSection(profile: empty)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.profileMusicTasteHeading), findsNothing);
    });

    testWidgets('renders a partial selection', (tester) async {
      const artistsOnly = PublicMusicProfile(
        enabled: true,
        artists: [PublicMusicArtist(id: 'a1', name: 'Lana Del Rey')],
      );
      await tester.pumpWidget(
        _wrap(const PublicMusicTasteSection(profile: artistsOnly)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lana Del Rey'), findsOneWidget);
    });
  });

  group('public profile parsing', () {
    test('drops anything beyond the published limits', () {
      final parsed = PublicMusicProfile.parse({
        'enabled': true,
        'artists': List.generate(
          8,
          (i) => {'id': 'a$i', 'name': 'Artist $i'},
        ),
        'tracks': List.generate(8, (i) => {'id': 't$i', 'name': 'Track $i'}),
        'genres': ['g1', 'g2', 'g3', 'g4', 'g5'],
      });

      expect(parsed.artists.length, maxPublicMusicArtists);
      expect(parsed.tracks.length, maxPublicMusicTracks);
      expect(parsed.genres.length, maxPublicMusicGenres);
    });

    test('a malformed payload becomes a hidden profile', () {
      expect(PublicMusicProfile.parse(null).hasContent, isFalse);
      expect(PublicMusicProfile.parse('nope').hasContent, isFalse);
      expect(PublicMusicProfile.parse(const {}).hasContent, isFalse);
    });

    test('entries without an id are skipped', () {
      final parsed = PublicMusicProfile.parse({
        'enabled': true,
        'artists': [
          {'name': 'No Id'},
          {'id': '', 'name': 'Blank'},
          {'id': 'a1', 'name': 'Real'},
        ],
      });
      expect(parsed.artists.map((a) => a.name), ['Real']);
    });
  });
}
