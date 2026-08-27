import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/presentation/controllers/music_controller.dart';
import 'package:mevora/features/music/presentation/pages/music_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  testWidgets('unconnected music tab shows connect CTA', (tester) async {
    final controller = MusicController(
      repository: MusicRepositoryImpl(dataSource: MockMusicDataSource()),
    );
    await tester.pumpWidget(wrap(MusicPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text(_en.musicConnectCta), findsOneWidget);
    expect(find.text(_en.musicUnconnectedCopy), findsOneWidget);
    expect(find.text(_en.musicConnected), findsNothing);
  });

  testWidgets('connected music tab shows same-taste list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = MockMusicDataSource();
    await source.connectSpotify();
    final controller = MusicController(
      repository: MusicRepositoryImpl(dataSource: source),
    );
    await tester.pumpWidget(wrap(MusicPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text(_en.musicConnected), findsOneWidget);
    expect(find.text(_en.musicSameTasteTitle), findsOneWidget);
    expect(find.textContaining('Ada'), findsWidgets);
    expect(find.textContaining('91'), findsWidgets);
  });

  testWidgets('connected music tab shows disconnect CTA', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = MockMusicDataSource();
    await source.connectSpotify();
    final controller = MusicController(
      repository: MusicRepositoryImpl(dataSource: source),
    );
    await tester.pumpWidget(wrap(MusicPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text(_en.musicConnected), findsOneWidget);
    expect(find.text(_en.musicDisconnectCta), findsOneWidget);
  });

  testWidgets('profile details hide music badge before match', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const candidate = DiscoveryCandidate(
      uid: 'music-ada',
      displayName: 'Ada',
      age: 27,
      compatibilityScore: 78,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
      musicCompatibilityScore: 91,
    );
    await tester.pumpWidget(
      wrap(const DiscoveryProfileDetailsPage(candidate: candidate)),
    );
    await tester.pumpAndSettle();

    expect(find.text(_en.musicCompatibilityPercent(91)), findsNothing);
    expect(find.text(_en.musicCompatibilityShort(91)), findsNothing);
    expect(find.text(_en.compatDiscoverBadge(78)), findsWidgets);
  });
}
