import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';

class MatchListItem {
  const MatchListItem({
    required this.match,
    required this.otherUserId,
    required this.name,
    this.photoUrl,
    this.presence = PresenceStatus.offline,
  });

  final Match match;
  final String otherUserId;
  final String name;
  final String? photoUrl;
  final PresenceStatus presence;

  int unreadCount(String uid) => match.unreadFor(uid);

  bool get showNewMatchBadge => match.lastMessage == null && match.isActive;
}
