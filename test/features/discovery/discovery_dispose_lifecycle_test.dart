import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/profile/profile_update_notifier.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Hub whose profile read is held open until the test releases it, so the page
/// can be disposed while the load is still in flight — the exact shape of
/// logout and account deletion.
class _SlowHub implements SettingsHubRepository {
  final Completer<UserProfile?> gate = Completer<UserProfile?>();
  int loadCalls = 0;

  @override
  Future<UserProfile?> loadProfile(String uid) {
    loadCalls += 1;
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorage implements StorageRepository {
  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    return Success(Uri.parse('https://example.com/$path'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReauth implements ReauthPort {
  @override
  Future<void> reauthenticateWithGoogle() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}
}

SettingsServices _services(SettingsHubRepository hub) {
  return SettingsServices(
    settingsHub: hub,
    photoManager: ProfilePhotoManager(settingsHub: hub, storage: _FakeStorage()),
    reauthService: _FakeReauth(),
    photoPicker: const StubProfilePhotoPicker(),
    profileUpdates: ProfileUpdateNotifier(),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  testWidgets(
    'a viewer-profile load that finishes after disposal never touches context',
    (tester) async {
      final hub = _SlowHub();

      await tester.pumpWidget(
        _wrap(SettingsScope(services: _services(hub), child: const DiscoveryPage())),
      );
      await tester.pump();

      expect(
        hub.loadCalls,
        greaterThan(0),
        reason: 'the page must have started a viewer-profile load',
      );

      // Tear the page down mid-load, exactly as the auth redirect does on
      // logout / account deletion.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump();

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      // Release the in-flight load against the now-disposed page.
      hub.gate.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      FlutterError.onError = previousOnError;

      expect(
        tester.takeException(),
        isNull,
        reason: 'the late load must not throw',
      );
      expect(
        errors.map((e) => e.exceptionAsString()).toList(),
        isEmpty,
        reason:
            'a delayed Discovery load must not read State.context after dispose '
            '(regression: "This widget has been unmounted, so the State no '
            'longer has a context")',
      );
    },
  );

  testWidgets('the viewer-profile loader still resolves while mounted', (
    tester,
  ) async {
    final hub = _SlowHub();

    await tester.pumpWidget(
      _wrap(SettingsScope(services: _services(hub), child: const DiscoveryPage())),
    );
    await tester.pump();

    hub.gate.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(hub.loadCalls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
