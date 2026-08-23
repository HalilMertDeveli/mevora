import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/domain/services/presence_subtitle.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  test('chat header prefers typing over online and last seen', () {
    final l10n = lookupAppLocalizations(const Locale('tr'));
    const privacy = UserPrivacy(uid: 'b');
    final presence = PresenceWatch(
      isOnline: true,
      updatedAt: DateTime(2026, 8, 23, 14, 30),
    );

    expect(
      PresenceSubtitle.chatHeader(
        l10n: l10n,
        presence: presence,
        privacy: privacy,
        isTyping: true,
      ),
      l10n.presenceTyping,
    );
    expect(
      PresenceSubtitle.chatHeader(
        l10n: l10n,
        presence: presence,
        privacy: privacy,
        isTyping: false,
      ),
      l10n.presenceOnline,
    );
  });

  test('last seen respects privacy and stale heartbeat', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 8, 23, 15, 0);
    final presence = PresenceWatch(
      isOnline: true,
      updatedAt: now.subtract(const Duration(minutes: 2)),
      lastSeenAt: now.subtract(const Duration(hours: 1)),
    );

    expect(
      PresenceSubtitle.chatHeader(
        l10n: l10n,
        presence: presence,
        privacy: const UserPrivacy(uid: 'b', showOnlineStatus: false),
        isTyping: false,
      ),
      L10nFormat.lastSeen(l10n, presence.lastSeenAt!, now: now),
    );

    expect(
      PresenceSubtitle.chatHeader(
        l10n: l10n,
        presence: presence,
        privacy: const UserPrivacy(uid: 'b', showLastSeen: false),
        isTyping: false,
      ),
      isNull,
    );
  });

  test('stale heartbeat is treated as offline for viewers', () {
    final now = DateTime(2026, 8, 23, 15, 0);
    final presence = PresenceWatch(
      isOnline: true,
      updatedAt: now.subtract(const Duration(minutes: 3)),
    );

    expect(presence.isEffectivelyOnline(PresenceSubtitle.staleAfter, now: now), isFalse);
  });
}
