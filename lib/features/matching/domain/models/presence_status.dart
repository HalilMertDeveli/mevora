import 'package:mevora/l10n/app_localizations.dart';

/// Coarse presence. Never expose an exact last-seen timestamp.
enum PresenceStatus { online, recentlyActive, offline, hidden }

extension PresenceStatusX on PresenceStatus {
  String get labelTr => switch (this) {
    PresenceStatus.online => 'Çevrimiçi',
    PresenceStatus.recentlyActive => 'Yakınlarda aktif',
    PresenceStatus.offline => 'Çevrimdışı',
    PresenceStatus.hidden => '',
  };

  String labelFor(AppLocalizations l10n) => switch (this) {
    PresenceStatus.online => l10n.presenceOnline,
    PresenceStatus.recentlyActive => l10n.presenceRecentlyActive,
    PresenceStatus.offline => l10n.presenceOffline,
    PresenceStatus.hidden => '',
  };

  static PresenceStatus fromUpdatedAt({
    required DateTime? updatedAt,
    required bool hideOnlineStatus,
    DateTime? now,
  }) {
    if (hideOnlineStatus) {
      return PresenceStatus.hidden;
    }
    if (updatedAt == null) {
      return PresenceStatus.offline;
    }
    final current = now ?? DateTime.now();
    final delta = current.difference(updatedAt);
    if (delta.inMinutes <= 5) {
      return PresenceStatus.online;
    }
    if (delta.inHours <= 24) {
      return PresenceStatus.recentlyActive;
    }
    return PresenceStatus.offline;
  }
}
