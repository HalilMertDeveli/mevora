import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/app_operations/data/app_operations_stores.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/presentation/controllers/app_operations_controller.dart';
import 'package:mevora/features/app_operations/presentation/pages/maintenance_page.dart';
import 'package:mevora/features/app_operations/presentation/pages/update_required_page.dart';
import 'package:mevora/features/app_operations/presentation/widgets/app_operations_banner_host.dart';
import 'package:mevora/features/app_operations/presentation/widgets/feature_unavailable_view.dart';
import 'package:mevora/features/music/data/datasources/mock_music_data_source.dart';
import 'package:mevora/features/music/data/repositories/music_repository_impl.dart';
import 'package:mevora/features/music/presentation/widgets/onboarding_music_step.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'app_operations_fakes.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

Future<AppOperationsController> _controller(
  WidgetTester tester,
  AppOperationsConfig config, {
  MemoryAppOperationsStore? store,
  String version = '1.0.1',
}) async {
  final controller = fakeOperationsController(
    cached: config,
    store: store ?? MemoryAppOperationsStore(config: config),
    version: version,
  )..start();
  addTearDown(controller.dispose);
  return controller;
}

Widget _app(
  AppOperationsController? controller,
  Widget home, {
  Locale locale = const Locale('en'),
  bool withHost = false,
}) {
  final app = MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: withHost
        ? (context, child) =>
              AppOperationsBannerHost(child: child ?? const SizedBox.shrink())
        : null,
    home: home,
  );
  return controller == null
      ? app
      : AppOperationsScope(controller: controller, child: app);
}

void main() {
  group('MaintenancePage', () {
    testWidgets('shows the default copy, in Turkish too', (tester) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(maintenanceEnabled: true),
      );
      await tester.pumpWidget(_app(controller, const MaintenancePage()));
      await tester.pump();
      expect(find.text(_en.appOpsMaintenanceTitle), findsOneWidget);
      expect(find.text(_en.appOpsMaintenanceMessage), findsOneWidget);
      // Signed out: no support/account buttons that would only bounce back.
      expect(find.text(_en.appOpsMaintenanceSupport), findsNothing);

      await tester.pumpWidget(
        _app(controller, const MaintenancePage(), locale: const Locale('tr')),
      );
      await tester.pump();
      expect(
        find.text('Mevora kısa süreli bakımda. Birazdan tekrar buradayız.'),
        findsOneWidget,
      );
      expect(_tr.appOpsMaintenanceMessage, isNot(_en.appOpsMaintenanceMessage));
    });

    testWidgets('shows the server message as plain text', (tester) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(
          maintenanceEnabled: true,
          maintenanceMessage: '<b>Back at 10:00</b>',
        ),
      );
      await tester.pumpWidget(_app(controller, const MaintenancePage()));
      await tester.pump();
      expect(find.text('<b>Back at 10:00</b>'), findsOneWidget);
      expect(find.text(_en.appOpsMaintenanceMessage), findsNothing);
    });
  });

  group('UpdateRequiredPage', () {
    testWidgets('opens the store link', (tester) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(
          minimumVersion: PlatformValues(android: '2.0.0'),
          updateUrl: PlatformValues(android: 'https://play.example/app'),
        ),
      );
      final opened = <Uri>[];
      await tester.pumpWidget(
        _app(
          controller,
          UpdateRequiredPage(
            launcher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_en.appOpsUpdateRequiredTitle), findsOneWidget);

      await tester.tap(find.text(_en.appOpsUpdateAction));
      await tester.pump();
      expect(opened, [Uri.parse('https://play.example/app')]);
    });

    testWidgets('without a link, names the store instead', (tester) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(
          minimumVersion: PlatformValues(android: '2.0.0'),
        ),
      );
      await tester.pumpWidget(_app(controller, const UpdateRequiredPage()));
      await tester.pump();
      expect(find.text(_en.appOpsUpdateAction), findsNothing);
      expect(
        find.textContaining(_en.appOpsUpdateFromStore('Google Play')),
        findsOneWidget,
      );
    });
  });

  group('announcement banner', () {
    testWidgets('shows app-wide and stays dismissed', (tester) async {
      final store = MemoryAppOperationsStore(
        config: const AppOperationsConfig(
          announcement: AppAnnouncement(
            id: 'a1',
            title: 'Heads up',
            message: '<i>Plain</i> text only',
            severity: AnnouncementSeverity.warning,
          ),
        ),
      );
      final controller = await _controller(tester, store.config!, store: store);
      await tester.pumpWidget(
        _app(controller, const Scaffold(body: Text('home')), withHost: true),
      );
      await tester.pump();
      expect(find.byKey(const Key('appOpsAnnouncementBanner')), findsOneWidget);
      expect(find.text('<i>Plain</i> text only'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);

      await tester.tap(find.byKey(const Key('appOpsAnnouncementDismiss')));
      await tester.pump();
      expect(find.byKey(const Key('appOpsAnnouncementBanner')), findsNothing);
      expect(store.dismissedAnnouncementId, 'a1');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('is hidden during maintenance', (tester) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(
          maintenanceEnabled: true,
          announcement: AppAnnouncement(id: 'a1', message: 'Hi'),
        ),
      );
      await tester.pumpWidget(
        _app(controller, const MaintenancePage(), withHost: true),
      );
      await tester.pump();
      expect(find.byKey(const Key('appOpsAnnouncementBanner')), findsNothing);
    });

    testWidgets('the soft update prompt is dismissible', (tester) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(
          recommendedVersion: PlatformValues(android: '1.5.0'),
        ),
      );
      await tester.pumpWidget(
        _app(controller, const Scaffold(body: Text('home')), withHost: true),
      );
      await tester.pump();
      expect(find.text(_en.appOpsUpdateAvailable), findsOneWidget);

      await tester.tap(find.byKey(const Key('appOpsUpdateDismiss')));
      await tester.pump();
      expect(find.text(_en.appOpsUpdateAvailable), findsNothing);
    });

    testWidgets('keeps the page state when a banner comes and goes', (
      tester,
    ) async {
      final repository = FakeAppOperationsRepository();
      final controller = fakeOperationsController(repository: repository)
        ..start();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(controller, const _Counter(), withHost: true),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('count 1'), findsOneWidget);

      repository.emit(
        const AppOperationsConfig(
          announcement: AppAnnouncement(id: 'x', message: 'News'),
        ),
      );
      await tester.pump();
      expect(find.text('News'), findsOneWidget);
      expect(find.text('count 1'), findsOneWidget);
    });
  });

  group('feature switches', () {
    testWidgets('Spotify off: onboarding hides Connect but can be skipped', (
      tester,
    ) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(disabledFeatures: {AppFeature.spotify}),
      );
      var skipped = false;
      await tester.pumpWidget(
        _app(
          controller,
          Scaffold(
            body: OnboardingMusicStep(
              repository: MusicRepositoryImpl(
                dataSource: MockMusicDataSource(),
              ),
              onSkip: () => skipped = true,
              onFinished: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_en.onboardingMusicConnect), findsNothing);
      expect(find.text(_en.appOpsSpotifyUnavailable), findsOneWidget);

      await tester.tap(find.text(_en.onboardingMusicSkip));
      expect(skipped, isTrue);
    });

    testWidgets('Spotify on (or no scope): Connect is offered', (tester) async {
      await tester.pumpWidget(
        _app(
          null,
          Scaffold(
            body: OnboardingMusicStep(
              repository: MusicRepositoryImpl(
                dataSource: MockMusicDataSource(),
              ),
              onSkip: () {},
              onFinished: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_en.onboardingMusicConnect), findsOneWidget);
      expect(find.text(_en.appOpsSpotifyUnavailable), findsNothing);
    });

    testWidgets('Boost off: a direct visit shows the unavailable screen', (
      tester,
    ) async {
      final controller = await _controller(
        tester,
        const AppOperationsConfig(disabledFeatures: {AppFeature.boost}),
      );
      await tester.pumpWidget(
        _app(
          controller,
          const AppFeatureGate(
            feature: AppFeature.boost,
            child: Text('boost screen'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('boost screen'), findsNothing);
      expect(find.text(_en.appOpsFeatureUnavailableTitle), findsOneWidget);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('count $_count'),
      ),
    );
  }
}
