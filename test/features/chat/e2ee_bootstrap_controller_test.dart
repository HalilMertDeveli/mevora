import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/chat/e2ee/services/e2ee_bootstrap_controller.dart';

class _FakeUidSource implements AuthUidSource {
  _FakeUidSource(this._controller);

  final StreamController<String?> _controller;
  String? _uid;

  @override
  String? get currentUid => _uid;

  @override
  Stream<String?> watchUid() => _controller.stream;

  void emit(String? uid) {
    _uid = uid;
    _controller.add(uid);
  }
}

class _RecordingBootstrap implements E2eeIdentityBootstrapPort {
  final bootstrapped = <String>[];
  var resetCount = 0;

  @override
  Future<void> bootstrap(String uid) async {
    bootstrapped.add(uid);
  }

  @override
  Future<void> reset() async {
    resetCount += 1;
  }
}

void main() {
  test('E2eeBootstrapController publishes identity on sign-in', () async {
    final uidController = StreamController<String?>.broadcast();
    final uidSource = _FakeUidSource(uidController);
    final bootstrapPort = _RecordingBootstrap();
    final bootstrap = E2eeBootstrapController(
      uidSource: uidSource,
      identityBootstrap: bootstrapPort,
    )..attach();

    uidSource.emit('user-a');
    await Future<void>.delayed(Duration.zero);

    expect(bootstrapPort.bootstrapped, ['user-a']);

    uidSource.emit('user-b');
    await Future<void>.delayed(Duration.zero);

    expect(bootstrapPort.resetCount, 1);
    expect(bootstrapPort.bootstrapped, ['user-a', 'user-b']);

    bootstrap.dispose();
    await uidController.close();
  });
}
