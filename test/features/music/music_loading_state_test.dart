import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/music/presentation/controllers/music_controller.dart';
import 'package:mevora/features/music/presentation/pages/music_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

/// Serves a scripted sequence of `getProfile` results so a test can model a
/// failed load followed by a successful retry.
class _ScriptedMusicRepository implements MusicRepository {
  _ScriptedMusicRepository(this._profiles);

  final List<Result<MusicProfile>> _profiles;
  int profileCalls = 0;

  @override
  Future<Result<MusicProfile>> getProfile() async {
    final index = profileCalls < _profiles.length
        ? profileCalls
        : _profiles.length - 1;
    profileCalls += 1;
    return _profiles[index];
  }

  @override
  Future<Result<MusicProfile>> connectSpotify() async =>
      const Success(MusicProfile(connected: true));

  @override
  Future<Result<void>> disconnectSpotify() async => const Success(null);

  @override
  Future<Result<MusicProfile>> syncTaste() async =>
      const Success(MusicProfile(connected: true));

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
  group('MusicController.load', () {
    test('a failed profile request is not a disconnected account', () async {
      final controller = MusicController(
        repository: _ScriptedMusicRepository(const [
          Err<MusicProfile>(NetworkFailure('offline')),
        ]),
      );

      await controller.load();

      expect(controller.state.isLoading, isFalse, reason: 'must settle');
      expect(controller.state.loadFailed, isTrue);
      expect(controller.state.connected, isFalse);
      expect(controller.state.failure, isA<NetworkFailure>());
    });

    test('a disconnected account is a successful empty result', () async {
      final controller = MusicController(
        repository: _ScriptedMusicRepository(const [
          Success(MusicProfile.disconnected),
        ]),
      );

      await controller.load();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.loadFailed, isFalse);
      expect(controller.state.connected, isFalse);
      expect(controller.state.failure, isNull);
    });

    test('a retry after a failure clears the failed state', () async {
      final repository = _ScriptedMusicRepository(const [
        Err<MusicProfile>(NetworkFailure('offline')),
        Success(MusicProfile(connected: true, spotifyUserId: 'sp-1')),
      ]);
      final controller = MusicController(repository: repository);

      await controller.load();
      expect(controller.state.loadFailed, isTrue);

      await controller.load();

      expect(controller.state.loadFailed, isFalse);
      expect(controller.state.connected, isTrue);
      expect(controller.state.failure, isNull);
      expect(repository.profileCalls, 2);
    });
  });

  group('MusicPage', () {
    testWidgets('a failed load offers a retry, not the connect CTA', (
      tester,
    ) async {
      final controller = MusicController(
        repository: _ScriptedMusicRepository(const [
          Err<MusicProfile>(NetworkFailure('offline')),
        ]),
      );

      await tester.pumpWidget(_wrap(MusicPage(controller: controller)));
      await tester.pumpAndSettle();

      // The account may well be connected — the request simply did not come
      // back. Telling the user to connect Spotify would be a lie.
      expect(find.text(_en.musicConnectCta), findsNothing);
      expect(find.text(_en.retry), findsOneWidget);
      expect(find.text(_en.musicNetwork), findsOneWidget);
    });

    testWidgets('retry re-requests the profile and renders it', (tester) async {
      final repository = _ScriptedMusicRepository(const [
        Err<MusicProfile>(NetworkFailure('offline')),
        Success(MusicProfile(connected: true, spotifyUserId: 'sp-1')),
      ]);
      final controller = MusicController(repository: repository);

      await tester.pumpWidget(_wrap(MusicPage(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.retry));
      await tester.pumpAndSettle();

      expect(repository.profileCalls, 2);
      expect(find.text(_en.retry), findsNothing);
      expect(find.text(_en.musicConnected), findsOneWidget);
    });

    testWidgets('a genuinely disconnected account still gets the CTA', (
      tester,
    ) async {
      final controller = MusicController(
        repository: _ScriptedMusicRepository(const [
          Success(MusicProfile.disconnected),
        ]),
      );

      await tester.pumpWidget(_wrap(MusicPage(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text(_en.musicConnectCta), findsOneWidget);
      expect(find.text(_en.retry), findsNothing);
    });
  });
}
