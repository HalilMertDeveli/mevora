import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  final en = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 8, 23, 12, 0);

  group('Match.occurredAt', () {
    test('prefers matchedAt over createdAt', () {
      final match = Match(
        id: 'a_b',
        userIds: ['a', 'b'],
        createdAt: DateTime.utc(2026, 8, 20),
        matchedAt: DateTime.utc(2026, 8, 22),
        isActive: true,
      );
      expect(match.occurredAt, DateTime.utc(2026, 8, 22));
    });

    test('falls back to createdAt when matchedAt is null', () {
      final match = Match(
        id: 'a_b',
        userIds: ['a', 'b'],
        createdAt: DateTime.utc(2026, 8, 20),
        isActive: true,
      );
      expect(match.occurredAt, DateTime.utc(2026, 8, 20));
    });

    test('does not use lastMessageAt for match elapsed time', () {
      final occurredAt = now.subtract(const Duration(days: 3, hours: 2));
      final match = Match(
        id: 'a_b',
        userIds: ['a', 'b'],
        createdAt: occurredAt,
        matchedAt: occurredAt,
        lastMessageAt: now.subtract(const Duration(minutes: 1)),
        isActive: true,
      );
      expect(
        L10nFormat.compactDate(tr, match.occurredAt, now: now),
        tr.timeDays(3),
      );
      expect(
        L10nFormat.compactDate(tr, match.lastMessageAt, now: now),
        tr.timeMinutes(1),
      );
    });
  });

  group('L10nFormat.compactDate', () {
    test('shows now for brand-new matches', () {
      expect(
        L10nFormat.compactDate(tr, now.subtract(const Duration(seconds: 10)), now: now),
        tr.timeNow,
      );
    });

    test('shows distinct minute values for older matches', () {
      expect(
        L10nFormat.compactDate(tr, now.subtract(const Duration(minutes: 5)), now: now),
        tr.timeMinutes(5),
      );
      expect(
        L10nFormat.compactDate(tr, now.subtract(const Duration(minutes: 23)), now: now),
        tr.timeMinutes(23),
      );
      expect(
        L10nFormat.compactDate(en, now.subtract(const Duration(hours: 2)), now: now),
        en.timeHours(2),
      );
      expect(
        L10nFormat.compactDate(tr, now.subtract(const Duration(days: 2)), now: now),
        tr.timeDays(2),
      );
    });

    test('never shows zero minutes after the now threshold', () {
      expect(
        L10nFormat.compactDate(tr, now.subtract(const Duration(seconds: 50)), now: now),
        tr.timeMinutes(1),
      );
    });

    test('clamps future timestamps to now', () {
      expect(
        L10nFormat.compactDate(tr, now.add(const Duration(minutes: 5)), now: now),
        tr.timeNow,
      );
    });
  });

  group('firestoreDate', () {
    test('parses Firestore timestamps for match fields', () {
      final createdAt = firestoreDate(Timestamp.fromDate(DateTime.utc(2026, 8, 20, 9)));
      final matchedAt = firestoreDate(Timestamp.fromDate(DateTime.utc(2026, 8, 22, 15)));
      final lastMessageAt = firestoreDate(
        Timestamp.fromDate(DateTime.utc(2026, 8, 23, 11, 59)),
      );
      expect(createdAt, isNotNull);
      expect(matchedAt, isNotNull);
      expect(lastMessageAt, isNotNull);
      expect(matchedAt!.isAfter(createdAt!), isTrue);
    });
  });
}
