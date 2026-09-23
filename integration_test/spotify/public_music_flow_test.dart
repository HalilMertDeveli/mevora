// Runtime QA for the Spotify public Music Taste flow.
//
// Runs the real widget tree on a device/emulator against the in-memory music
// source, so the selection limits, the publish call and the cross-profile
// rendering are exercised for real without needing interactive Spotify
// authorization.
//
//   flutter test integration_test/spotify/public_music_flow_test.dart \
//     -d emulator-5554
//
// Real Spotify OAuth is covered separately by manual acceptance; nothing here
// contacts Spotify.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/presentation/controllers/public_music_controller.dart';
import 'package:mevora/features/music/presentation/pages/public_music_selection_page.dart';
import 'package:mevora/features/music/presentation/widgets/onboarding_music_step.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_taste_section.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

MusicProfile _imported() {
  return MusicProfile(
    connected: true,
    spotifyUserId: 'spotify-user-1',
    displayName: 'Listener',
    topArtists: const [
      MusicArtist(id: 'a1', name: 'Arctic Monkeys', genres: ['indie']),
      MusicArtist(id: 'a2', name: 'The Weeknd', genres: ['r&b']),
      MusicArtist(id: 'a3', name: 'Lana Del Rey', genres: ['indie']),
      MusicArtist(id: 'a4', name: 'Radiohead', genres: ['alternative']),
    ],
    topTracks: const [
      MusicTrack(id: 't1', name: '505', artist: 'AM'),
      MusicTrack(id: 't2', name: 'After Hours', artist: 'TW'),
      MusicTrack(id: 't3', name: 'Do I Wanna Know?', artist: 'AM'),
      MusicTrack(id: 't4', name: 'Creep', artist: 'RH'),
    ],
    genres: const [GenreShare(name: 'indie', percent: 50)],
    taste: const MusicTasteSnapshot(artistIds: ['a1'], trackIds: ['t1']),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA1 — onboarding music can be skipped', (tester) async {
    var skipped = false;
    final source = MockMusicDataSource(connectedProfile: _imported());
    await tester.pumpWidget(
      _wrap(
        OnboardingMusicStep(
          repository: MusicRepositoryImpl(dataSource: source),
          onSkip: () => skipped = true,
          onFinished: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_en.onboardingMusicTitle), findsOneWidget);
    await tester.tap(find.text(_en.onboardingMusicSkip));
    await tester.pumpAndSettle();

    expect(skipped, isTrue);
    expect(source.connectCalls, 0);
  });

  testWidgets('QA2/QA3 — connect, select 3, refuse a 4th, publish', (
    tester,
  ) async {
    final source = MockMusicDataSource(connectedProfile: _imported());
    var finished = false;
    await tester.pumpWidget(
      _wrap(
        OnboardingMusicStep(
          repository: MusicRepositoryImpl(dataSource: source),
          onSkip: () {},
          onFinished: () => finished = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_en.onboardingMusicConnect));
    await tester.pumpAndSettle();
    expect(source.connectCalls, 1);
    expect(find.text(_en.publicMusicTitle), findsOneWidget);

    for (final name in ['Arctic Monkeys', 'The Weeknd', 'Lana Del Rey']) {
      await tester.ensureVisible(find.text(name));
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    expect(find.text(_en.publicMusicArtistCount(3, 3)), findsOneWidget);

    // The fourth must not be accepted.
    await tester.ensureVisible(find.text('Radiohead'));
    await tester.tap(find.text('Radiohead'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text(_en.publicMusicArtistCount(3, 3)), findsOneWidget);

    await tester.ensureVisible(find.text(_en.publicMusicSave));
    await tester.tap(find.text(_en.publicMusicSave));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(source.publicMusicUpdateCalls, 1);

    // QA3 persistence: the source now reports the published selection.
    final reloaded = await source.getProfile();
    expect(reloaded.publicProfile.enabled, isTrue);
    expect(reloaded.publicProfile.artists.length, 3);
  });

  testWidgets('QA4/QA5/QA6 — a viewer sees only what is published', (
    tester,
  ) async {
    final source = MockMusicDataSource(connectedProfile: _imported());
    await source.connectSpotify();
    final repository = MusicRepositoryImpl(dataSource: source);
    final controller = PublicMusicController(
      repository: repository,
      profile: await source.getProfile(),
    );

    await tester.pumpWidget(
      _wrap(PublicMusicSelectionPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arctic Monkeys'));
    await tester.ensureVisible(find.text('505'));
    await tester.tap(find.text('505'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(_en.publicMusicSave));
    await tester.tap(find.text(_en.publicMusicSave));
    await tester.pumpAndSettle();

    // QA4 — the viewer's side of the profile.
    final published = (await source.getProfile()).publicProfile;
    await tester.pumpWidget(
      _wrap(PublicMusicTasteSection(profile: published)),
    );
    await tester.pumpAndSettle();
    expect(find.text(_en.profileMusicTasteHeading), findsOneWidget);
    expect(find.text('Arctic Monkeys'), findsOneWidget);
    expect(find.text('505'), findsOneWidget);
    // Nothing the owner did not choose.
    expect(find.text('Radiohead'), findsNothing);
    expect(find.text('Creep'), findsNothing);

    // QA5 — hiding it removes the section for viewers.
    await source.updatePublicMusicProfile(
      enabled: false,
      artistIds: published.artistIds,
      trackIds: published.trackIds,
    );
    final hidden = (await source.getProfile()).publicProfile;
    await tester.pumpWidget(_wrap(PublicMusicTasteSection(profile: hidden)));
    await tester.pumpAndSettle();
    expect(find.text(_en.profileMusicTasteHeading), findsNothing);
    expect(
      (await source.getProfile()).connected,
      isTrue,
      reason: 'hiding must not disconnect Spotify',
    );

    // QA6 — re-enabling brings the same selection back.
    await source.updatePublicMusicProfile(
      enabled: true,
      artistIds: published.artistIds,
      trackIds: published.trackIds,
    );
    final reshown = (await source.getProfile()).publicProfile;
    await tester.pumpWidget(_wrap(PublicMusicTasteSection(profile: reshown)));
    await tester.pumpAndSettle();
    expect(find.text('Arctic Monkeys'), findsOneWidget);
  });

  testWidgets('QA8 — disconnect leaves no Music Taste behind', (tester) async {
    final source = MockMusicDataSource(connectedProfile: _imported());
    await source.connectSpotify();
    await source.updatePublicMusicProfile(
      enabled: true,
      artistIds: const ['a1'],
      trackIds: const ['t1'],
    );
    expect((await source.getProfile()).publicProfile.hasContent, isTrue);

    await source.disconnectSpotify();

    final after = await source.getProfile();
    expect(after.connected, isFalse);
    expect(after.publicProfile.hasContent, isFalse);

    await tester.pumpWidget(
      _wrap(PublicMusicTasteSection(profile: after.publicProfile)),
    );
    await tester.pumpAndSettle();
    expect(find.text(_en.profileMusicTasteHeading), findsNothing);
  });
}
