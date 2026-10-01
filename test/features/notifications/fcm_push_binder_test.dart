import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';
import 'package:mevora/features/notifications/data/fcm_push_binder.dart';

typedef _Registration = ({String uid, String token});

class _FakeMessaging implements FirebaseMessagingDataSource {
  String? token = 'token-1';
  final registrations = <_Registration>[];
  final tokenRefresh = StreamController<String>.broadcast();
  Completer<void>? tokenGate;
  Object? registerError;

  @override
  Future<Result<String?>> getToken() async {
    await tokenGate?.future;
    return Success(token);
  }

  @override
  Stream<String> watchTokenRefresh() => tokenRefresh.stream;

  @override
  Stream<Map<String, dynamic>> watchOpenedApp() => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> watchForegroundMessage() => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;

  @override
  Future<void> registerDevice({
    required String uid,
    required String token,
  }) async {
    final error = registerError;
    if (error != null) {
      registerError = null;
      throw error;
    }
    registrations.add((uid: uid, token: token));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeMessaging messaging;
  late MutableAuthUidSource auth;
  late FcmPushBinder binder;

  FcmPushBinder build(String? uid) {
    messaging = _FakeMessaging();
    auth = MutableAuthUidSource(uid);
    binder = FcmPushBinder(
      router: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        ],
      ),
      services: createGraphSocialServices(
        graph: InMemorySocialGraph(),
        uidSource: auth,
      ),
      messaging: messaging,
    );
    addTearDown(binder.dispose);
    return binder;
  }

  Future<void> settle() => pumpEventQueue();

  test('signed out at start: nothing is registered', () async {
    await build(null).attach();
    await settle();

    expect(messaging.registrations, isEmpty);
  });

  test('signed in at start: the token is registered once', () async {
    await build('aya').attach();
    // The auth stream reports the member who was already signed in.
    auth.uid = 'aya';
    await settle();

    expect(messaging.registrations, [(uid: 'aya', token: 'token-1')]);
  });

  test('sign-in after a signed-out start registers exactly once', () async {
    await build(null).attach();

    auth.uid = 'aya';
    await settle();

    expect(messaging.registrations, [(uid: 'aya', token: 'token-1')]);
  });

  test(
    'repeated auth emissions for the same member do not write again',
    () async {
      await build(null).attach();

      auth.uid = 'aya';
      await settle();
      auth.uid = 'aya';
      auth.uid = 'aya';
      await settle();

      expect(messaging.registrations, [(uid: 'aya', token: 'token-1')]);
    },
  );

  test(
    'sign out, then another member signs in: the token moves to them',
    () async {
      await build('aya').attach();

      auth.uid = null;
      await settle();
      auth.uid = 'can';
      await settle();

      expect(messaging.registrations, [
        (uid: 'aya', token: 'token-1'),
        (uid: 'can', token: 'token-1'),
      ]);
    },
  );

  test('the same member signing back in is registered again', () async {
    // Sign-out removes the device document, so the next sign-in must write it.
    await build('aya').attach();

    auth.uid = null;
    await settle();
    auth.uid = 'aya';
    await settle();

    expect(messaging.registrations, [
      (uid: 'aya', token: 'token-1'),
      (uid: 'aya', token: 'token-1'),
    ]);
  });

  test('an auth emission while the token is still loading does not double '
      'register', () async {
    build('aya');
    messaging.tokenGate = Completer<void>();
    final attached = binder.attach();
    await settle();

    auth.uid = 'aya';
    await settle();
    messaging.tokenGate!.complete();
    await attached;
    await settle();

    expect(messaging.registrations, [(uid: 'aya', token: 'token-1')]);
  });

  test(
    'a member who signs in while the token loads is the one registered',
    () async {
      build(null);
      messaging.tokenGate = Completer<void>();
      final attached = binder.attach();
      await settle();

      auth.uid = 'can';
      await settle();
      messaging.tokenGate!.complete();
      await attached;
      await settle();

      expect(messaging.registrations, [(uid: 'can', token: 'token-1')]);
    },
  );

  test('a token refresh registers the new token once', () async {
    await build(null).attach();
    auth.uid = 'aya';
    await settle();

    messaging.token = 'token-2';
    messaging.tokenRefresh.add('token-2');
    await settle();

    expect(messaging.registrations, [
      (uid: 'aya', token: 'token-1'),
      (uid: 'aya', token: 'token-2'),
    ]);
  });

  test(
    'a failed sign-in registration is retried on the next auth emission',
    () async {
      await build(null).attach();
      messaging.registerError = StateError('offline');

      auth.uid = 'aya';
      await settle();
      expect(messaging.registrations, isEmpty);

      auth.uid = 'aya';
      await settle();
      expect(messaging.registrations, [(uid: 'aya', token: 'token-1')]);
    },
  );

  test('no token yet: nothing is written on sign-in', () async {
    await build(null).attach();
    messaging.token = null;

    auth.uid = 'aya';
    await settle();

    expect(messaging.registrations, isEmpty);
  });

  test('after dispose a sign-in registers nothing', () async {
    await build(null).attach();
    binder.dispose();

    auth.uid = 'aya';
    await settle();

    expect(messaging.registrations, isEmpty);
  });
}
