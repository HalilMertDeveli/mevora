import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/datasources/music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/presentation/controllers/music_controller.dart';
import 'package:mevora/features/music/presentation/pages/music_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// Data source whose profile read fails or stalls on demand, standing in for
/// an unreachable callable, a failed App Check attestation or a dead network.
class _FlakyMusicDataSource implements MusicDataSource {
  bool failProfile = true;
  Completer<MusicProfile>? stall;
  int profileCalls = 0;

  @override
  Future<MusicProfile> getProfile() {
    profileCalls += 1;
    final pending = stall;
    if (pending != null) {
      return pending.future;
    }
    if (failProfile) {
      return Future<MusicProfile>.error(
        const NetworkException('Device is offline.'),
      );
    }
    return Future.value(MockMusicDataSource.seedProfile);
  }

  @override
  Future<MusicProfile> connectSpotify() async => MockMusicDataSource.seedProfile;

  @override
  Future<void> disconnectSpotify() async {}

  @override
  Future<MusicProfile> syncTaste() async => MockMusicDataSource.seedProfile;

  @override
  Future<WeeklyMusicStats> getWeeklyStats() async => WeeklyMusicStats.empty;

  @override
  Future<List<SameTasteMatch>> getSameTasteProfiles() async => const [];

  @override
  Future<MatchMusicCompatibility> getMatchMusicCompatibility(String matchId) {
    throw UnimplementedError();
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  group('MusicController.load', () {
    test('settles and flags the failure when the backend is unreachable', () async {
      final controller = MusicController(
        repository: MusicRepositoryImpl(dataSource: _FlakyMusicDataSource()),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.loadFailed, isTrue);
      expect(controller.state.failure, isNotNull);
    });

    test('a disconnected account settles to disconnected, not to a failure', () async {
      final controller = MusicController(
        repository: MusicRepositoryImpl(dataSource: MockMusicDataSource()),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.loadFailed, isFalse);
      expect(controller.state.connected, isFalse);
      expect(controller.state.failure, isNull);
    });

    test('retrying after a failure clears the error state', () async {
      final source = _FlakyMusicDataSource();
      final controller = MusicController(
        repository: MusicRepositoryImpl(dataSource: source),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.loadFailed, isTrue);

      source.failProfile = false;
      await controller.load();

      expect(controller.state.loadFailed, isFalse);
      expect(controller.state.failure, isNull);
      expect(controller.state.connected, isTrue);
      expect(source.profileCalls, 2);
    });
  });

  group('MusicPage', () {
    testWidgets('stays on the spinner only while the profile read is pending', (
      tester,
    ) async {
      final source = _FlakyMusicDataSource()..stall = Completer<MusicProfile>();
      final controller = MusicController(
        repository: MusicRepositoryImpl(dataSource: source),
      );
      await tester.pumpWidget(_wrap(MusicPage(controller: controller)));
      await tester.pump();

      expect(find.byType(MevoraLoading), findsWidgets);

      source.stall!.completeError(
        const NetworkException('Callable timed out.'),
      );
      await tester.pumpAndSettle();

      // The slow path settles into an error rather than an endless spinner.
      expect(find.byType(MevoraLoading), findsNothing);
      expect(find.byType(MevoraErrorView), findsOneWidget);
      controller.dispose();
    });

    testWidgets('a failed load shows a retryable error, not the connect CTA', (
      tester,
    ) async {
      final source = _FlakyMusicDataSource();
      final controller = MusicController(
        repository: MusicRepositoryImpl(dataSource: source),
      );
      await tester.pumpWidget(_wrap(MusicPage(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.byType(MevoraErrorView), findsOneWidget);
      expect(find.text(_en.musicConnectCta), findsNothing);
      // No fabricated taste data reaches the UI on failure.
      expect(find.text(_en.musicConnected), findsNothing);

      source.failProfile = false;
      await tester.tap(find.text(_en.retry));
      await tester.pumpAndSettle();

      expect(find.byType(MevoraErrorView), findsNothing);
      expect(find.text(_en.musicConnected), findsOneWidget);
      controller.dispose();
    });

    testWidgets('a disconnected account still resolves to the connect CTA', (
      tester,
    ) async {
      final controller = MusicController(
        repository: MusicRepositoryImpl(dataSource: MockMusicDataSource()),
      );
      await tester.pumpWidget(_wrap(MusicPage(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text(_en.musicConnectCta), findsOneWidget);
      expect(find.byType(MevoraErrorView), findsNothing);
      controller.dispose();
    });
  });
}
