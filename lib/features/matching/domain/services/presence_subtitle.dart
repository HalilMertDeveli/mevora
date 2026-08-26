import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// WhatsApp-style chat header subtitle: typing > online > last seen.
abstract final class PresenceSubtitle {
  static const Duration staleAfter = Duration(seconds: 90);

  static String? chatHeader({
    required AppLocalizations l10n,
    required PresenceWatch? presence,
    required UserPrivacy? privacy,
    required bool isTyping,
  }) {
    if (isTyping && showsTyping(privacy)) {
      return l10n.presenceTyping;
    }
    return presenceLine(l10n: l10n, presence: presence, privacy: privacy);
  }

  static String? presenceLine({
    required AppLocalizations l10n,
    required PresenceWatch? presence,
    required UserPrivacy? privacy,
  }) {
    if (presence == null) {
      return null;
    }
    if (showsOnline(privacy) && presence.isEffectivelyOnline(staleAfter)) {
      return l10n.presenceOnline;
    }
    if (!showsLastSeen(privacy)) {
      return null;
    }
    final lastSeen = presence.lastSeenAt ?? presence.updatedAt;
    if (lastSeen == null) {
      return null;
    }
    return L10nFormat.lastSeen(l10n, lastSeen);
  }

  static PresenceStatus listBadge({
    required PresenceWatch? presence,
    required UserPrivacy? privacy,
  }) {
    if (!showsOnline(privacy)) {
      return PresenceStatus.hidden;
    }
    if (presence != null && presence.isEffectivelyOnline(staleAfter)) {
      return PresenceStatus.online;
    }
    return PresenceStatus.offline;
  }

  static bool showsOnline(UserPrivacy? privacy) =>
      privacy?.showOnlineStatus ?? true;

  static bool showsLastSeen(UserPrivacy? privacy) =>
      privacy?.showLastSeen ?? privacy?.showActivity ?? true;

  static bool showsTyping(UserPrivacy? privacy) =>
      privacy?.showTypingStatus ?? true;
}

extension PresenceWatchX on PresenceWatch {
  bool isEffectivelyOnline(Duration staleAfter, {DateTime? now}) {
    if (!isOnline) {
      return false;
    }
    final beat = updatedAt;
    if (beat == null) {
      return false;
    }
    return (now ?? DateTime.now()).difference(beat) <= staleAfter;
  }
}
