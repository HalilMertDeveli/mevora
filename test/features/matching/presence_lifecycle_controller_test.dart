import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/domain/services/presence_subtitle.dart';
import 'package:mevora/features/matching/presentation/controllers/presence_lifecycle_controller.dart';

/// Replays the current uid on listen, like FirebaseAuth.authStateChanges.
class _ReplayingUid implements AuthUidSource {
  _ReplayingUid(this.currentUid);

  @override
  final String? currentUid;

  @override
  Stream<String?> watchUid() => Stream.value(currentUid);
}

class _RecordingPresence implements PresenceRepository {
  final List<String> writes = [];

  @override
  Stream<PresenceWatch> watch(String uid) => const Stream.empty();

  @override
  Future<void> setOnline(String uid) async => writes.add('online');

  @override
  Future<void> setOffline(String uid) async => writes.add('offline');

  @override
  Future<void> heartbeat(String uid) async => writes.add('beat');
}

void main() {
  late _RecordingPresence presence;
  late PresenceLifecycleController controller;

  Future<void> attachInForeground(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    presence = _RecordingPresence();
    controller = PresenceLifecycleController(
      presenceRepository: presence,
      uidSource: _ReplayingUid('me'),
    )..attach();
    await tester.pump();
  }

  testWidgets('coming online writes once, not once per auth replay', (
    tester,
  ) async {
    await attachInForeground(tester);
    expect(presence.writes, ['online']);
    controller.dispose();
  });

  testWidgets('beats once per interval while in the foreground', (
    tester,
  ) async {
    await attachInForeground(tester);
    await tester.pump(const Duration(minutes: 5));
    expect(presence.writes, ['online', 'beat', 'beat', 'beat', 'beat', 'beat']);
    controller.dispose();
  });

  testWidgets('a notification-shade flicker does not rewrite presence', (
    tester,
  ) async {
    await attachInForeground(tester);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(presence.writes, ['online']);
    controller.dispose();
  });

  testWidgets('pause goes offline and resume comes back online', (
    tester,
  ) async {
    await attachInForeground(tester);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 5));
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(presence.writes, ['online', 'offline', 'online']);
    controller.dispose();
  });

  testWidgets(
    'an Android background trip writes offline once and online once',
    (tester) async {
      await attachInForeground(tester);
      // Going out: inactive, hidden, paused. Coming back: hidden, inactive,
      // resumed.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        controller.didChangeAppLifecycleState(state);
      }
      await tester.pump();
      expect(presence.writes, ['online', 'offline', 'online']);
      controller.dispose();
    },
  );

  test('a controller that never went online writes nothing on dispose', () {
    final presence = _RecordingPresence();
    PresenceLifecycleController(
      presenceRepository: presence,
      uidSource: _ReplayingUid('me'),
    ).dispose();
    expect(presence.writes, isEmpty);
  });

  test('viewers tolerate two missed beats', () {
    expect(
      PresenceSubtitle.staleAfter,
      greaterThan(PresenceLifecycleController.heartbeatInterval * 2),
    );
  });
}
