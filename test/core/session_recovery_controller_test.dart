import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/session/session_recovery_controller.dart';

void main() {
  test('SessionRecoveryController recovers without Firebase singletons', () async {
    final controller = SessionRecoveryController.detached();
    await controller.recover(reason: 'test');
    controller.dispose();
  });
}
