import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/discovery/data/repositories/mock_discovery_repository.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/discovery/presentation/controllers/discovery_controller.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

/// Controller backed by the mock deck, location prompt skipped.
/// [missingProfiles] are the uids whose profile probe reports "deleted".
Future<DiscoveryController> _loadedController({
  Set<String> missingProfiles = const {},
  List<String>? probeLog,
  bool probeThrows = false,
}) async {
  final controller = DiscoveryController(
    uid: 'self',
    locationRepository: FakeLocationRepository(
      permission: LocationPermissionStatus.denied,
    ),
    discoveryRepository: MockDiscoveryRepository(),
    viewerProfileLoader: (uid) async {
      probeLog?.add(uid);
      // Only candidate probes fail; the viewer's own profile still loads, which
      // is what a network blip against a single document looks like.
      if (probeThrows && uid != 'self') {
        throw StateError('probe unavailable');
      }
      if (missingProfiles.contains(uid)) {
        return null;
      }
      return UserProfile(uid: uid, displayName: 'Profile $uid');
    },
  );
  await controller.skipLocation();
  return controller;
}

DiscoveryController _controllerFor(MockDiscoveryRepository repo) {
  return DiscoveryController(
    uid: 'self',
    locationRepository: FakeLocationRepository(
      permission: LocationPermissionStatus.denied,
    ),
    discoveryRepository: repo,
  );
}

void main() {
  group('evictCandidates', () {
    test('removes the visible candidate and advances to the next', () async {
      final controller = await _loadedController();
      final deck = controller.state.candidates;
      expect(deck.length, greaterThan(2), reason: 'need a multi-card deck');
      final first = deck.first.uid;
      final second = deck[1].uid;

      controller.evictCandidates([first]);

      expect(controller.state.candidates.any((c) => c.uid == first), isFalse);
      expect(controller.state.current?.uid, second,
          reason: 'the next card must become current, not a blank deck');
      controller.dispose();
    });

    test('removes a queued candidate without disturbing the current card',
        () async {
      final controller = await _loadedController();
      final deck = controller.state.candidates;
      final first = deck.first.uid;
      final third = deck[2].uid;

      controller.evictCandidates([third]);

      expect(controller.state.current?.uid, first,
          reason: 'evicting a queued card must not advance the deck');
      expect(controller.state.candidates.any((c) => c.uid == third), isFalse);
      controller.dispose();
    });

    test('is a no-op for a uid that was never on the deck', () async {
      final controller = await _loadedController();
      final before = controller.state.candidates.map((c) => c.uid).toList();

      controller.evictCandidates(['someone-who-was-never-here']);

      expect(controller.state.candidates.map((c) => c.uid).toList(), before);
      controller.dispose();
    });

    test('is idempotent', () async {
      final controller = await _loadedController();
      final first = controller.state.candidates.first.uid;

      controller.evictCandidates([first]);
      final afterFirst = controller.state.candidates.map((c) => c.uid).toList();
      controller.evictCandidates([first]);
      controller.evictCandidates([first]);

      expect(controller.state.candidates.map((c) => c.uid).toList(), afterFirst);
      controller.dispose();
    });

    test('ignores empty uids', () async {
      final controller = await _loadedController();
      final before = controller.state.candidates.length;
      controller.evictCandidates(['', '']);
      expect(controller.state.candidates.length, before);
      controller.dispose();
    });

    test('an evicted candidate is not re-admitted by a later load', () async {
      // The server stops returning a deleted user, but a prefetch already in
      // flight can still carry the old card; the guard has to survive a reload.
      final controller = await _loadedController();
      final evicted = controller.state.candidates.first.uid;
      controller.evictCandidates([evicted]);

      await controller.refresh();

      expect(controller.state.candidates.any((c) => c.uid == evicted), isFalse,
          reason: 'a reload must not resurrect an evicted candidate');
      controller.dispose();
    });

    test('drops the cached compatibility breakdown for the evicted candidate',
        () async {
      final controller = await _loadedController();
      final candidate = controller.state.candidates.first;
      // Populate the session cache for this pair.
      controller.breakdownFor(candidate);

      controller.evictCandidates([candidate.uid]);

      expect(controller.state.candidates.any((c) => c.uid == candidate.uid),
          isFalse);
      controller.dispose();
    });
  });

  group('revalidateVisibleCandidates', () {
    test('evicts a candidate whose profile is gone', () async {
      final controller = await _loadedController();
      final gone = controller.state.candidates.first.uid;
      final next = controller.state.candidates[1].uid;

      final revalidating = await _loadedController(missingProfiles: {gone});
      // Re-create with the same deck order so uids line up.
      expect(revalidating.state.candidates.first.uid, gone);

      await revalidating.revalidateVisibleCandidates();

      expect(revalidating.state.candidates.any((c) => c.uid == gone), isFalse);
      expect(revalidating.state.current?.uid, next);
      controller.dispose();
      revalidating.dispose();
    });

    test('only probes the visible stack, not the whole deck', () async {
      final probed = <String>[];
      final controller = await _loadedController(probeLog: probed);
      final deckSize = controller.state.candidates.length;
      expect(deckSize, greaterThan(3), reason: 'deck must exceed the stack');
      probed.clear();

      await controller.revalidateVisibleCandidates();

      expect(probed.length, lessThanOrEqualTo(3),
          reason: 'revalidation must stay bounded to the visible stack');
      expect(probed.length, lessThan(deckSize));
      controller.dispose();
    });

    test('keeps the card when the probe fails', () async {
      // A network failure is not proof of deletion.
      final controller = await _loadedController(probeThrows: true);
      final before = controller.state.candidates.map((c) => c.uid).toList();

      await controller.revalidateVisibleCandidates();

      expect(controller.state.candidates.map((c) => c.uid).toList(), before);
      controller.dispose();
    });

    test('is safe on an empty deck', () async {
      final controller = await _loadedController();
      controller.evictCandidates(
        controller.state.candidates.map((c) => c.uid).toList(),
      );
      await controller.revalidateVisibleCandidates();
      controller.dispose();
    });
  });

  group('interaction after eviction', () {
    test('the evicted candidate is never liked, and the next one still can be',
        () async {
      final repo = MockDiscoveryRepository();
      final controller = _controllerFor(repo);
      await controller.skipLocation();
      final evicted = controller.state.candidates.first.uid;
      final next = controller.state.candidates[1].uid;

      controller.evictCandidates([evicted]);
      // A tap that lands after eviction must act on the next valid card, and
      // nothing may ever be recorded against the deleted account.
      await controller.decide(DiscoveryDecision.like);

      expect(repo.liked.contains(evicted), isFalse,
          reason: 'no like may be recorded against a deleted account');
      expect(repo.liked.contains(next), isTrue,
          reason: 'normal liking must keep working');
      controller.dispose();
    });

    test('the evicted candidate is never passed', () async {
      final repo = MockDiscoveryRepository();
      final controller = _controllerFor(repo);
      await controller.skipLocation();
      final evicted = controller.state.candidates.first.uid;

      controller.evictCandidates([evicted]);
      await controller.decide(DiscoveryDecision.pass);

      expect(repo.passed.contains(evicted), isFalse);
      controller.dispose();
    });
  });

  group('Discover screen', () {
    testWidgets('the evicted card disappears and the next one renders', (
      tester,
    ) async {
      final controller = await _loadedController();
      await tester.pumpWidget(_wrap(DiscoveryPage(controller: controller)));
      await tester.pumpAndSettle();

      final gone = controller.state.candidates.first;
      final next = controller.state.candidates[1];
      expect(find.textContaining(gone.displayName), findsWidgets);

      controller.evictCandidates([gone.uid]);
      await tester.pumpAndSettle();

      expect(find.textContaining(gone.displayName), findsNothing,
          reason: 'no stale name may survive on the deck');
      if (gone.bio != null && gone.bio!.isNotEmpty) {
        expect(find.textContaining(gone.bio!), findsNothing,
            reason: 'no stale bio may survive on the deck');
      }
      expect(find.textContaining(next.displayName), findsWidgets);
      controller.dispose();
    });
  });
}
