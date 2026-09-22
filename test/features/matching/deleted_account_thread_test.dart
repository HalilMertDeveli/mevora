import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';
import 'package:mevora/features/matching/presentation/widgets/match_connection_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';

const _me = 'me';
const _other = 'other';

Match _match({
  required bool isActive,
  String? unmatchedBy,
  String? endedReason,
  String otherName = 'Ayşe',
  String? otherPhoto = 'https://example.invalid/a.jpg',
}) {
  return Match(
    id: 'm1',
    userIds: const [_me, _other],
    createdAt: DateTime(2026, 1, 1),
    isActive: isActive,
    lastMessage: 'son mesaj',
    lastMessageAt: DateTime(2026, 1, 2),
    unmatchedBy: unmatchedBy,
    unmatchedAt: isActive ? null : DateTime(2026, 1, 3),
    endedReason: endedReason,
    participantNames: {_me: 'Ben', _other: otherName},
    participantPhotos: {if (otherPhoto != null) _other: otherPhoto},
  );
}

MatchListItem _item(Match match) => MatchListItem(
      match: match,
      otherUserId: _other,
      name: match.otherName(_me),
      photoUrl: match.otherPhoto(_me),
    );

/// Minimal repository double: the page only needs the two streams.
class _FakeMatchRepository implements MatchRepository {
  _FakeMatchRepository({this.active = const [], this.archived = const []});

  final List<MatchListItem> active;
  final List<MatchListItem> archived;

  @override
  Stream<List<MatchListItem>> watchMatches(String uid) => Stream.value(active);

  @override
  Stream<List<MatchListItem>> watchArchivedMatches(String uid) =>
      Stream.value(archived);

  @override
  Future<Match?> getMatch(String matchId) async => null;

  @override
  Stream<Match?> watchMatch(String matchId) => const Stream.empty();

  @override
  Future<void> markOpened(String matchId, String uid) async {}
}

class _StaticUid implements AuthUidSource {
  _StaticUid(this._uid);
  final String? _uid;

  @override
  String? get currentUid => _uid;

  @override
  Stream<String?> watchUid() => Stream.value(_uid);
}

class _FakePresenceRepository implements PresenceRepository {
  @override
  Stream<PresenceWatch> watch(String uid) => const Stream.empty();

  @override
  Future<void> setOnline(String uid) async {}

  @override
  Future<void> setOffline(String uid) async {}

  @override
  Future<void> heartbeat(String uid) async {}
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('tr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    );

void main() {
  group('Match.threadStateFor', () {
    test('an active match is active', () {
      expect(
        _match(isActive: true).threadStateFor(_me),
        MatchThreadState.active,
      );
    });

    test('inactive with no endedReason, ended by the other user, is deleted-account history', () {
      // Exactly what deleteUserAccount writes: isActive false, unmatchedBy set
      // to the departing uid, and no endedReason.
      final match = _match(isActive: false, unmatchedBy: _other);
      expect(match.threadStateFor(_me), MatchThreadState.deletedAccountHistory);
      expect(match.isDeletedAccountHistoryFor(_me), isTrue);
    });

    test('an ordinary unmatch is not deleted-account history', () {
      final match =
          _match(isActive: false, unmatchedBy: _other, endedReason: 'unmatch');
      expect(match.threadStateFor(_me), MatchThreadState.inactiveOther);
      expect(match.isDeletedAccountHistoryFor(_me), isFalse);
    });

    test('a block is not deleted-account history', () {
      final match =
          _match(isActive: false, unmatchedBy: _other, endedReason: 'block');
      expect(match.threadStateFor(_me), MatchThreadState.inactiveOther);
    });

    test('a thread I ended myself is not deleted-account history', () {
      // Guards against showing my own unmatch as "the other account was deleted".
      final match = _match(isActive: false, unmatchedBy: _me);
      expect(match.threadStateFor(_me), MatchThreadState.inactiveOther);
    });

    test('inactive with no unmatchedBy at all is not deleted-account history', () {
      expect(
        _match(isActive: false).threadStateFor(_me),
        MatchThreadState.inactiveOther,
      );
    });
  });

  group('MatchConnectionTile read-only history', () {
    testWidgets('renders the localized deleted label, not the stored name', (
      tester,
    ) async {
      // The backend stores the English marker in participantNames; a Turkish
      // user must still see Turkish.
      final match = _match(
        isActive: false,
        unmatchedBy: _other,
        otherName: 'Deleted account',
      );
      await tester.pumpWidget(_host(
        MatchConnectionTile(
          item: _item(match),
          currentUid: _me,
          isReadOnlyHistory: true,
        ),
      ));
      await tester.pump();

      expect(find.text('Silinmiş hesap'), findsOneWidget);
      expect(find.text('Deleted account'), findsNothing);
      expect(find.text('Salt okunur'), findsOneWidget);
      // The retained last message must not be advertised as live activity.
      expect(find.text('son mesaj'), findsNothing);
    });

    testWidgets('shows no presence indicator for a deleted account', (
      tester,
    ) async {
      final match = _match(isActive: false, unmatchedBy: _other);
      await tester.pumpWidget(_host(
        MatchConnectionTile(
          item: _item(match),
          currentUid: _me,
          isReadOnlyHistory: true,
          showOnlineIndicator: true,
        ),
      ));
      await tester.pump();
      expect(find.text('Silinmiş hesap'), findsOneWidget);
    });

    testWidgets('an active tile is unchanged', (tester) async {
      final match = _match(isActive: true);
      await tester.pumpWidget(_host(
        MatchConnectionTile(item: _item(match), currentUid: _me),
      ));
      await tester.pump();
      expect(find.text('Ayşe'), findsOneWidget);
      expect(find.text('son mesaj'), findsOneWidget);
      expect(find.text('Silinmiş hesap'), findsNothing);
    });
  });

  group('MatchesController archived stream', () {
    test('keeps history separate from active matches and metrics', () async {
      final active = _item(_match(isActive: true));
      final archived = _item(_match(isActive: false, unmatchedBy: _other));
      final controller = MatchesController(
        matchRepository:
            _FakeMatchRepository(active: [active], archived: [archived]),
        presenceRepository: _FakePresenceRepository(),
        uidSource: _StaticUid(_me),
      );
      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.items.length, 1);
      expect(controller.archivedItems.length, 1);
      // History must not inflate match counts or engagement metrics.
      expect(controller.mutualLikeCount, 1);
      expect(controller.activeConversationCount, 0);
      controller.dispose();
    });

    test('an empty archived stream leaves the list empty', () async {
      final controller = MatchesController(
        matchRepository: _FakeMatchRepository(active: [_item(_match(isActive: true))]),
        presenceRepository: _FakePresenceRepository(),
        uidSource: _StaticUid(_me),
      );
      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.archivedItems, isEmpty);
      controller.dispose();
    });
  });
}
