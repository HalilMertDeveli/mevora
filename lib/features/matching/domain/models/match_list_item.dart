import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';

class MatchListItem {
  const MatchListItem({
    required this.match,
    required this.otherUserId,
    required this.name,
    this.photoUrl,
    this.isVerified = false,
    this.presence = PresenceStatus.offline,
    this.compatibility,
  });

  final Match match;
  final String otherUserId;
  final String name;
  final String? photoUrl;
  final bool isVerified;
  final PresenceStatus presence;

  /// Viewer's snapshot at match time — null for legacy matches.
  final CompatibilitySnapshot? compatibility;

  CompatibilityBreakdown? get breakdown => compatibility?.breakdown;

  int unreadCount(String uid) => match.unreadFor(uid);

  bool get showNewMatchBadge => match.lastMessage == null && match.isActive;
}
