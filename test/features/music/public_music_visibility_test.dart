import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/music/presentation/pages/public_music_selection_page.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_visibility_card.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// Records what the card asked the backend to publish, and can fail on demand.
class _RecordingRepository implements MusicRepository {
  _RecordingRepository({this.failure, this.gate});

  final Failure? failure;

  /// When set, the write does not finish until this completes.
  final Completer<void>? gate;
  final calls =
      <({bool enabled, List<String> artistIds, List<String> trackIds})>[];

  @override
  Future<Result<PublicMusicProfile>> updatePublicMusicProfile({
    required bool enabled,
    required List<String> artistIds,
    required List<String> trackIds,
  }) async {
    calls.add((enabled: enabled, artistIds: artistIds, trackIds: trackIds));
    await gate?.future;
    final error = failure;
    if (error != null) {
      return Err(error);
    }
    return Success(
      PublicMusicProfile(
        enabled: enabled && (artistIds.isNotEmpty || trackIds.isNotEmpty),
        artists: artistIds
            .map((id) => PublicMusicArtist(id: id, name: 'Artist $id'))
            .toList(),
        tracks: trackIds
            .map((id) => PublicMusicTrack(id: id, name: 'Track $id'))
            .toList(),
      ),
    );
  }

  @override
  Future<Result<MusicProfile>> connectSpotify() async =>
      const Err(NetworkFailure('not used'));

  @override
  Future<Result<MusicProfile>> getProfile() async =>
      const Err(NetworkFailure('not used'));

  @override
  Future<Result<MusicProfile>> syncTaste() async =>
      const Err(NetworkFailure('not used'));

  @override
  Future<Result<void>> disconnectSpotify() async =>
      const Err(NetworkFailure('not used'));

  @override
  Future<Result<WeeklyMusicStats>> getWeeklyStats() async =>
      const Err(NetworkFailure('not used'));

  @override
  Future<Result<List<SameTasteMatch>>> getSameTasteProfiles() async =>
      const Err(NetworkFailure('not used'));

  @override
  Future<Result<MatchMusicCompatibility>> getMatchMusicCompatibility(
    String matchId,
  ) async => const Err(NetworkFailure('not used'));
}

MusicProfile _profileWith(PublicMusicProfile published) {
  return MusicProfile(
    connected: true,
    spotifyUserId: 'spotify-user-1',
    displayName: 'Listener',
    topArtists: const [MusicArtist(id: 'a1', name: 'Artist 1')],
    topTracks: const [MusicTrack(id: 't1', name: 'Track 1', artist: 'Band')],
    publicProfile: published,
  );
}

const _published = PublicMusicProfile(
  enabled: true,
  artists: [PublicMusicArtist(id: 'a1', name: 'Artist 1')],
  tracks: [PublicMusicTrack(id: 't1', name: 'Track 1')],
);

/// The same selection, hidden. This is the state the switch used to die in.
const _hidden = PublicMusicProfile(
  artists: [PublicMusicArtist(id: 'a1', name: 'Artist 1')],
  tracks: [PublicMusicTrack(id: 't1', name: 'Track 1')],
);

Future<void> _pump(
  WidgetTester tester,
  MusicRepository repository,
  PublicMusicProfile published,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: PublicMusicVisibilityCard(
          repository: repository,
          profile: _profileWith(published),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hiding the card leaves the switch usable', (tester) async {
    final repository = _RecordingRepository();
    await _pump(tester, repository, _hidden);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse);
    expect(
      toggle.onChanged,
      isNotNull,
      reason: 'a member who hid their music must be able to show it again',
    );
  });

  testWidgets('turning it back on republishes the same selection', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await _pump(tester, repository, _hidden);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.enabled, isTrue);
    expect(repository.calls.single.artistIds, ['a1']);
    expect(repository.calls.single.trackIds, ['t1']);
  });

  testWidgets('a hidden selection is announced, not silently dropped', (
    tester,
  ) async {
    await _pump(tester, _RecordingRepository(), _hidden);
    expect(find.text(_en.publicMusicHiddenNotice), findsOneWidget);
  });

  testWidgets('with nothing chosen, turning it on opens the picker', (
    tester,
  ) async {
    // A switch that ignored the tap read as broken: Spotify was connected and
    // the top artists were on screen, but nothing had been picked to show.
    final repository = _RecordingRepository();
    await _pump(tester, repository, PublicMusicProfile.hidden);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNotNull);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.byType(PublicMusicSelectionPage), findsOneWidget);
    expect(
      repository.calls,
      isEmpty,
      reason: 'there is nothing to publish until the member picks something',
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('a visible card can be turned off', (tester) async {
    final repository = _RecordingRepository();
    await _pump(tester, repository, _published);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repository.calls.single.enabled, isFalse);
  });

  testWidgets('a failed change says so instead of pretending', (tester) async {
    final repository = _RecordingRepository(
      failure: const NetworkFailure('Spotify is unreachable'),
    );
    await _pump(tester, repository, _hidden);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Spotify is unreachable'), findsOneWidget);
  });

  testWidgets('the switch moves as soon as it is tapped', (tester) async {
    // Against a real backend the write takes a moment. A control that does not
    // move until it returns reads as broken, which is what was reported.
    final gate = Completer<void>();
    final repository = _RecordingRepository(gate: gate);
    await _pump(tester, repository, _published);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isFalse,
      reason: 'the tap must be visible before the write comes back',
    );
    expect(repository.calls.single.enabled, isFalse);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed write rolls the switch back', (tester) async {
    final repository = _RecordingRepository(
      failure: const NetworkFailure('Spotify is unreachable'),
    );
    await _pump(tester, repository, _published);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isTrue,
      reason: 'nothing was stored, so the switch must show the stored value',
    );
    expect(find.text('Spotify is unreachable'), findsOneWidget);
  });

  testWidgets('the preview follows the switch, not the stored value', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _RecordingRepository(gate: gate);
    await _pump(tester, repository, _published);
    expect(find.text('Artist 1'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(
      find.text('Artist 1'),
      findsNothing,
      reason: 'the card should go as soon as the member turns it off',
    );

    gate.complete();
    await tester.pumpAndSettle();
  });
}
