import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/app_operations/data/app_operations_stores.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_operations_fakes.dart';

const _maintenance = AppOperationsConfig(
  revision: 2,
  maintenanceEnabled: true,
  maintenanceMessage: 'Back soon',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with nothing cached and no document it is normal operation', () async {
    final repository = FakeAppOperationsRepository();
    final controller = fakeOperationsController(repository: repository)
      ..start();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.gate, AppOperationsGate.normal);
    expect(controller.activeAnnouncement, isNull);
    for (final feature in AppFeature.values) {
      expect(controller.isFeatureEnabled(feature), isTrue);
    }
    expect(repository.watchCalls, 1);
  });

  test('a cached document applies before the network answers', () {
    final controller = fakeOperationsController(cached: _maintenance)..start();
    addTearDown(controller.dispose);

    // Synchronously: the very first frame is already gated.
    expect(controller.gate, AppOperationsGate.maintenance);
    expect(controller.maintenanceMessage, 'Back soon');
  });

  test('follows the live document and caches every valid snapshot', () async {
    final repository = FakeAppOperationsRepository();
    final store = MemoryAppOperationsStore();
    final controller = fakeOperationsController(
      repository: repository,
      store: store,
    )..start();
    addTearDown(controller.dispose);
    var notified = 0;
    controller.addListener(() => notified++);

    repository.emit(_maintenance);
    await pumpEventQueue();
    expect(controller.gate, AppOperationsGate.maintenance);
    expect(store.config, _maintenance);
    expect(notified, greaterThan(0));

    repository.emit(AppOperationsConfig.defaults);
    await pumpEventQueue();
    expect(controller.gate, AppOperationsGate.normal);
    expect(store.config, AppOperationsConfig.defaults);
  });

  test('a stream error keeps the last valid config', () async {
    final repository = FakeAppOperationsRepository();
    final controller = fakeOperationsController(repository: repository)
      ..start();
    addTearDown(controller.dispose);

    repository.emit(
      const AppOperationsConfig(disabledFeatures: {AppFeature.boost}),
    );
    await pumpEventQueue();
    repository.fail(Exception('permission-denied'));
    await pumpEventQueue();

    expect(controller.isFeatureEnabled(AppFeature.boost), isFalse);
    expect(controller.gate, AppOperationsGate.normal);

    // The listener is gone after an error; resuming opens a fresh one.
    controller.refresh();
    expect(repository.watchCalls, 2);
  });

  test('without Firebase it still starts, from the cache', () async {
    final repository = FakeAppOperationsRepository()..throwOnWatch = true;
    final controller = fakeOperationsController(
      repository: repository,
      cached: _maintenance,
    )..start();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(controller.gate, AppOperationsGate.maintenance);
  });

  test('restores from SharedPreferences across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final online = FakeAppOperationsRepository();
    final first = fakeOperationsController(
      repository: online,
      store: SharedPreferencesAppOperationsStore(preferences),
    )..start();
    online.emit(_maintenance);
    await pumpEventQueue();
    first.dispose();

    // Next cold start, offline: the document never arrives.
    final offline = FakeAppOperationsRepository()..throwOnWatch = true;
    final second = fakeOperationsController(
      repository: offline,
      store: SharedPreferencesAppOperationsStore(preferences),
    )..start();
    addTearDown(second.dispose);
    expect(second.gate, AppOperationsGate.maintenance);

    // A corrupt cache entry is no cache at all, never a gate.
    await preferences.setString(
      SharedPreferencesAppOperationsStore.configKey,
      '{not json',
    );
    final third = fakeOperationsController(
      repository: offline,
      store: SharedPreferencesAppOperationsStore(preferences),
    )..start();
    addTearDown(third.dispose);
    expect(third.gate, AppOperationsGate.normal);
  });

  test('the installed version drives the update gate', () async {
    final repository = FakeAppOperationsRepository();
    final controller = fakeOperationsController(
      repository: repository,
      version: '1.0.1',
    )..start();
    addTearDown(controller.dispose);
    await pumpEventQueue();

    repository.emit(
      const AppOperationsConfig(
        maintenanceEnabled: true,
        minimumVersion: PlatformValues(android: '1.1.0'),
        updateUrl: PlatformValues(android: 'https://play.example/app'),
      ),
    );
    await pumpEventQueue();
    expect(controller.gate, AppOperationsGate.updateRequired);
    expect(controller.updateUrl, 'https://play.example/app');
  });

  test('the soft prompt is dismissed once per recommended version', () async {
    final repository = FakeAppOperationsRepository();
    final store = MemoryAppOperationsStore();
    final controller = fakeOperationsController(
      repository: repository,
      store: store,
    )..start();
    addTearDown(controller.dispose);
    repository.emit(
      const AppOperationsConfig(
        recommendedVersion: PlatformValues(android: '1.2.0'),
      ),
    );
    await pumpEventQueue();
    expect(controller.showUpdateRecommendation, isTrue);

    await controller.dismissUpdateRecommendation();
    expect(controller.showUpdateRecommendation, isFalse);
    expect(store.dismissedRecommendedVersion, '1.2.0');

    repository.emit(
      const AppOperationsConfig(
        recommendedVersion: PlatformValues(android: '1.3.0'),
      ),
    );
    await pumpEventQueue();
    expect(controller.showUpdateRecommendation, isTrue);
  });

  test('a dismissed announcement stays dismissed, a new id shows', () async {
    final repository = FakeAppOperationsRepository();
    final store = MemoryAppOperationsStore();
    final controller = fakeOperationsController(
      repository: repository,
      store: store,
    )..start();
    addTearDown(controller.dispose);
    repository.emit(
      const AppOperationsConfig(
        announcement: AppAnnouncement(id: 'a1', message: 'Hello'),
      ),
    );
    await pumpEventQueue();
    expect(controller.activeAnnouncement?.id, 'a1');

    await controller.dismissAnnouncement();
    expect(controller.activeAnnouncement, isNull);
    expect(store.dismissedAnnouncementId, 'a1');

    repository.emit(
      const AppOperationsConfig(
        announcement: AppAnnouncement(id: 'a2', message: 'Again'),
      ),
    );
    await pumpEventQueue();
    expect(controller.activeAnnouncement?.id, 'a2');
  });

  testWidgets('an announcement appears and expires on time', (tester) async {
    var now = DateTime(2026, 10, 1, 8, 59, 59);
    final controller = fakeOperationsController(
      cached: AppOperationsConfig(
        announcement: AppAnnouncement(
          id: 'win',
          message: 'Windowed',
          startsAt: DateTime(2026, 10, 1, 9),
          expiresAt: DateTime(2026, 10, 1, 9, 0, 5),
        ),
      ),
      clock: () => now,
    )..start();
    addTearDown(controller.dispose);
    await tester.pump(); // installed version resolves
    var notified = 0;
    controller.addListener(() => notified++);
    expect(controller.activeAnnouncement, isNull);

    now = DateTime(2026, 10, 1, 9);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(notified, 1);
    expect(controller.activeAnnouncement?.id, 'win');

    now = DateTime(2026, 10, 1, 9, 0, 5);
    await tester.pump(const Duration(milliseconds: 5100));
    expect(notified, 2);
    expect(controller.activeAnnouncement, isNull);
  });

  test('the router hears only gate and humor changes', () async {
    final repository = FakeAppOperationsRepository();
    final controller = fakeOperationsController(repository: repository)
      ..start();
    addTearDown(controller.dispose);
    await pumpEventQueue();
    var routed = 0;
    controller.routing.addListener(() => routed++);

    repository.emit(
      const AppOperationsConfig(
        announcement: AppAnnouncement(id: 'a', message: 'm'),
        disabledFeatures: {AppFeature.boost},
      ),
    );
    await pumpEventQueue();
    expect(routed, 0);

    repository.emit(const AppOperationsConfig(maintenanceEnabled: true));
    await pumpEventQueue();
    expect(routed, 1);

    repository.emit(
      const AppOperationsConfig(
        maintenanceEnabled: true,
        disabledFeatures: {AppFeature.humorLab},
      ),
    );
    await pumpEventQueue();
    expect(routed, 2);
  });
}
