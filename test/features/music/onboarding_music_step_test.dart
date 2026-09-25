import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/music/presentation/widgets/onboarding_music_step.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(8), child: child),
    ),
  );
}

MusicProfile _imported({int artists = 4}) {
  return MusicProfile(
    connected: true,
    spotifyUserId: 'spotify-user-1',
    topArtists: List.generate(
      artists,
      (i) => MusicArtist(id: 'a$i', name: 'Artist $i'),
    ),
    topTracks: List.generate(
      3,
      (i) => MusicTrack(id: 't$i', name: 'Track $i', artist: 'Band $i'),
    ),
    taste: const MusicTasteSnapshot(artistIds: ['a0']),
  );
}

/// A repository whose connect outcome the test dictates.
class _ScriptedRepository implements MusicRepository {
  _ScriptedRepository(this._connectResult);

  final Result<MusicProfile> _connectResult;
  int connectCalls = 0;

  @override
  Future<Result<MusicProfile>> connectSpotify() async {
    connectCalls += 1;
    return _connectResult;
  }

  @override
  Future<Result<MusicProfile>> getProfile() async =>
      const Success(MusicProfile.disconnected);

  @override
  Future<Result<void>> disconnectSpotify() async => const Success(null);

  @override
  Future<Result<MusicProfile>> syncTaste() async =>
      const Success(MusicProfile.disconnected);

  @override
  Future<Result<PublicMusicProfile>> updatePublicMusicProfile({
    required bool enabled,
    required List<String> artistIds,
    required List<String> trackIds,
  }) async => const Success(PublicMusicProfile.hidden);

  @override
  Future<Result<WeeklyMusicStats>> getWeeklyStats() async =>
      const Success(WeeklyMusicStats.empty);

  @override
  Future<Result<List<SameTasteMatch>>> getSameTasteProfiles() async =>
      const Success(<SameTasteMatch>[]);

  @override
  Future<Result<MatchMusicCompatibility>> getMatchMusicCompatibility(
    String matchId,
  ) async => const Success(MatchMusicCompatibility.unavailable);
}

void main() {
  group('onboarding music step', () {
    testWidgets('asks the question and offers a skip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: _ScriptedRepository(
              const Success(MusicProfile.disconnected),
            ),
            onSkip: () {},
            onFinished: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.onboardingMusicTitle), findsOneWidget);
      expect(find.text(_en.onboardingMusicConnect), findsOneWidget);
      expect(find.text(_en.onboardingMusicSkip), findsOneWidget);
    });

    testWidgets('skipping continues onboarding without connecting', (
      tester,
    ) async {
      var skipped = false;
      final repository = _ScriptedRepository(
        const Success(MusicProfile.disconnected),
      );
      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: repository,
            onSkip: () => skipped = true,
            onFinished: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.onboardingMusicSkip));
      await tester.pumpAndSettle();

      expect(skipped, isTrue);
      expect(repository.connectCalls, 0, reason: 'skip must not start OAuth');
    });

    testWidgets('a successful connect moves on to the selection', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: _ScriptedRepository(Success(_imported())),
            onSkip: () {},
            onFinished: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.onboardingMusicConnect));
      await tester.pumpAndSettle();

      expect(find.text(_en.publicMusicTitle), findsOneWidget);
      expect(find.text('Artist 0'), findsOneWidget);
    });

    testWidgets('a cancelled authorization offers retry or skip, not an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: _ScriptedRepository(
              const Err(
                AuthFailure('cancelled', kind: AuthErrorKind.cancelled),
              ),
            ),
            onSkip: () {},
            onFinished: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.onboardingMusicConnect));
      await tester.pumpAndSettle();

      // Backing out of Spotify is a choice, not a failure — onboarding state
      // is intact and both options remain.
      expect(find.text(_en.onboardingMusicCancelled), findsOneWidget);
      expect(find.text(_en.onboardingMusicConnect), findsOneWidget);
      expect(find.text(_en.onboardingMusicSkip), findsOneWidget);
    });

    testWidgets('a network failure is recoverable, not terminal', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: _ScriptedRepository(
              const Err(NetworkFailure('offline')),
            ),
            onSkip: () {},
            onFinished: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.onboardingMusicConnect));
      await tester.pumpAndSettle();

      expect(find.text(_en.onboardingMusicConnect), findsOneWidget);
      expect(find.text(_en.onboardingMusicSkip), findsOneWidget);
    });

    testWidgets('connecting an account with no data still moves on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: _ScriptedRepository(
              const Success(MusicProfile(connected: true)),
            ),
            onSkip: () {},
            onFinished: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.onboardingMusicConnect));
      await tester.pumpAndSettle();

      // Connected with limited data: say so, do not pretend it failed.
      expect(find.text(_en.publicMusicEmpty), findsOneWidget);
    });

    testWidgets('publishing a selection finishes the step', (tester) async {
      var finished = false;
      final source = MockMusicDataSource(connectedProfile: _imported());
      await source.connectSpotify();
      final repository = MusicRepositoryImpl(dataSource: source);

      await tester.pumpWidget(
        _wrap(
          OnboardingMusicStep(
            repository: repository,
            onSkip: () {},
            onFinished: () => finished = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.onboardingMusicConnect));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Artist 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.publicMusicSave));
      await tester.pumpAndSettle();

      expect(finished, isTrue);
      expect(source.publicMusicUpdateCalls, 1);
    });
  });

  group('onboarding step ordering', () {
    test('music sits after photos and before completion', () {
      expect(OnboardingStep.photos.next, OnboardingStep.music);
      expect(OnboardingStep.music.next, OnboardingStep.complete);
      expect(OnboardingStep.music.previous, OnboardingStep.photos);
    });

    test('stored progress still resolves', () {
      expect(OnboardingStep.fromStorage(7), OnboardingStep.photos);
      expect(OnboardingStep.fromStorage('music'), OnboardingStep.music);
      expect(OnboardingStep.fromStorage(9), OnboardingStep.complete);
    });

    test('skipping music is not required to complete onboarding', () {
      // Nothing about the enum marks music as mandatory; completion is still
      // the final step and the step itself is skippable in the UI.
      expect(OnboardingStep.complete.next, isNull);
      expect(OnboardingStep.values.last, OnboardingStep.complete);
    });
  });
}
