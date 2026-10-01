import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/features/notifications/data/push_navigator.dart';

/// A router with the three things that get in a notification's way in the
/// real app: the splash while the session is restored, a gate the member has
/// to pass first, and the redirect that enforces both.
GoRouter _router({
  required ValueNotifier<bool> signedIn,
  required ValueNotifier<bool> gated,
  String initialLocation = '/',
}) {
  Widget page(String label) => Scaffold(body: Text(label));
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: Listenable.merge([signedIn, gated]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!signedIn.value) {
        return location == '/' ? null : '/';
      }
      if (gated.value) {
        return location == '/gate' ? null : '/gate';
      }
      if (location == '/' || location == '/gate') {
        return '/discovery';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => page('splash')),
      GoRoute(path: '/gate', builder: (_, _) => page('gate')),
      GoRoute(path: '/discovery', builder: (_, _) => page('discovery')),
      GoRoute(path: '/matches', builder: (_, _) => page('matches')),
      GoRoute(path: '/settings', builder: (_, _) => page('settings')),
      GoRoute(path: '/boost', builder: (_, _) => page('boost')),
      GoRoute(
        path: '/chat/:matchId',
        builder: (_, state) => page('chat ${state.pathParameters['matchId']}'),
      ),
    ],
  );
}

void main() {
  late ValueNotifier<bool> signedIn;
  late ValueNotifier<bool> gated;
  late GoRouter router;
  late PushNavigator navigator;
  late DateTime now;

  Future<void> start(
    WidgetTester tester, {
    bool isSignedIn = true,
    bool isGated = false,
    String initialLocation = '/',
  }) async {
    signedIn = ValueNotifier(isSignedIn);
    gated = ValueNotifier(isGated);
    router = _router(
      signedIn: signedIn,
      gated: gated,
      initialLocation: initialLocation,
    );
    now = DateTime(2026, 10, 1, 12);
    navigator = PushNavigator(router: router, clock: () => now);
    addTearDown(navigator.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  /// The navigator waits on real timers between its steps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  String location() => router.state.uri.path;

  testWidgets('a conversation opens on top of Matches, so Back has a way out', (
    tester,
  ) async {
    await start(tester, initialLocation: '/settings');
    expect(location(), '/settings');

    navigator.open('/chat/m1');
    await settle(tester);

    expect(location(), '/chat/m1');
    expect(find.text('chat m1'), findsOneWidget);
    expect(navigator.pendingLocation, isNull);

    router.pop();
    await tester.pumpAndSettle();
    expect(location(), '/matches');
    expect(find.text('matches'), findsOneWidget);
  });

  testWidgets('already on Matches: the conversation is pushed, not replaced', (
    tester,
  ) async {
    await start(tester, initialLocation: '/matches');

    navigator.open('/chat/m1');
    await settle(tester);
    expect(location(), '/chat/m1');

    router.pop();
    await tester.pumpAndSettle();
    expect(location(), '/matches');
  });

  testWidgets('a tap on a cold start opens the conversation once the session '
      'is restored', (tester) async {
    await start(tester, isSignedIn: false);
    expect(location(), '/');

    navigator.open('/chat/m1');
    await settle(tester);
    // The redirect keeps the app on the splash; the destination is kept.
    expect(location(), '/');
    expect(navigator.pendingLocation, '/chat/m1');

    signedIn.value = true;
    await settle(tester);

    expect(location(), '/chat/m1');
    expect(navigator.pendingLocation, isNull);
    router.pop();
    await tester.pumpAndSettle();
    expect(location(), '/matches');
  });

  testWidgets(
    'a gate in the way is passed first, then the conversation opens',
    (tester) async {
      await start(tester, isGated: true);
      expect(location(), '/gate');

      navigator.open('/chat/m1');
      await settle(tester);
      expect(location(), '/gate');
      expect(navigator.pendingLocation, '/chat/m1');

      gated.value = false;
      await settle(tester);
      expect(location(), '/chat/m1');
    },
  );

  testWidgets('a destination that stayed blocked too long is dropped', (
    tester,
  ) async {
    await start(tester, isSignedIn: false);

    navigator.open('/chat/m1');
    await settle(tester);
    expect(navigator.pendingLocation, '/chat/m1');

    now = now.add(const Duration(minutes: 6));
    signedIn.value = true;
    await settle(tester);

    expect(location(), '/discovery');
    expect(navigator.pendingLocation, isNull);
  });

  testWidgets('a destination with no parent is opened directly', (
    tester,
  ) async {
    await start(tester, initialLocation: '/discovery');

    navigator.open('/boost');
    await settle(tester);

    expect(location(), '/boost');
    expect(navigator.pendingLocation, isNull);
  });

  testWidgets('a newer notification replaces one that is still waiting', (
    tester,
  ) async {
    await start(tester, isSignedIn: false);

    navigator.open('/chat/m1');
    await settle(tester);
    navigator.open('/chat/m2');
    await settle(tester);
    expect(navigator.pendingLocation, '/chat/m2');

    signedIn.value = true;
    await settle(tester);
    expect(location(), '/chat/m2');
  });
}
