import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';

void main() {
  group('refreshIdTokenWithDeadline', () {
    test('returns immediately when there is no signed-in user', () async {
      await expectLater(
        refreshIdTokenWithDeadline(null, deadline: const Duration(seconds: 10)),
        completes,
      );
    });

    test('awaits a refresh that completes', () async {
      var completed = false;
      final refresh = Future<Object?>.delayed(
        const Duration(milliseconds: 5),
        () {
          completed = true;
          return 'token';
        },
      );

      await refreshIdTokenWithDeadline(
        refresh,
        deadline: const Duration(seconds: 10),
      );

      expect(completed, isTrue);
    });

    test('settles when the refresh never completes', () async {
      // The regression: `getIdToken(true)` is a network round trip with no
      // deadline of its own, so a stalled connection left the caller — the
      // Music tab among others — pending forever, with nothing thrown and
      // nothing logged. This refresh never completes; the call must settle.
      final stalled = Completer<Object?>();
      addTearDown(() => stalled.complete(null));

      await refreshIdTokenWithDeadline(
        stalled.future,
        deadline: const Duration(milliseconds: 20),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('refresh was not bounded by its deadline'),
      );
    });

    test('does not give up before its deadline', () async {
      final slow = Future<Object?>.delayed(
        const Duration(milliseconds: 40),
        () => 'token',
      );
      var settledEarly = true;
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 10),
          () => settledEarly = false,
        ),
      );

      await refreshIdTokenWithDeadline(
        slow,
        deadline: const Duration(seconds: 5),
      );

      expect(settledEarly, isFalse);
    });

    test('a failed refresh is not fatal', () async {
      // A stale ID token is survivable: the callable retries once on
      // `unauthenticated`. Turning a refresh failure into a thrown error
      // would break calls that would otherwise have succeeded.
      await expectLater(
        refreshIdTokenWithDeadline(
          Future<Object?>.error(StateError('network down')),
          deadline: const Duration(seconds: 10),
        ),
        completes,
      );
    });
  });

  group('callablePayload', () {
    test('normalizes a null payload to an empty map', () {
      expect(callablePayload(null), isEmpty);
    });

    test('normalizes Map<Object?, Object?> with null values', () {
      final payload = callablePayload(<Object?, Object?>{
        'spotifyConnected': true,
        'displayName': null,
      });
      expect(payload['spotifyConnected'], isTrue);
      expect(payload.containsKey('displayName'), isTrue);
    });

    test('rejects a non-map payload', () {
      expect(() => callablePayload('nope'), throwsFormatException);
    });
  });
}
