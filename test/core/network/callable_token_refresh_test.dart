import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';

void main() {
  group('refreshIdTokenWithDeadline', () {
    test('returns as soon as the refresh completes', () async {
      var called = false;
      await refreshIdTokenWithDeadline(
        () async {
          called = true;
          return 'token';
        },
        timeout: const Duration(seconds: 5),
      );
      expect(called, isTrue);
    });

    test('gives up on a refresh that never completes', () async {
      // `User.getIdToken(true)` is a network round trip with no deadline of
      // its own. Before the deadline was added this await could hang forever
      // and every caller awaiting a callable — the Music tab included — was
      // left on an infinite spinner.
      final stalled = Completer<void>();
      addTearDown(() {
        if (!stalled.isCompleted) {
          stalled.complete();
        }
      });

      await expectLater(
        refreshIdTokenWithDeadline(
          () => stalled.future,
          timeout: const Duration(milliseconds: 50),
        ).timeout(const Duration(seconds: 2)),
        completes,
      );
    });

    test('swallows refresh errors so a stale token is not fatal', () async {
      // The callable retries once on `unauthenticated`, so a failed refresh
      // must not turn into a hard failure of its own.
      await expectLater(
        refreshIdTokenWithDeadline(
          () => Future<void>.error(StateError('network down')),
          timeout: const Duration(seconds: 5),
        ),
        completes,
      );
    });
  });
}
