import 'package:mevora/features/matching/domain/models/swipe_action.dart';

class LikeRecord {
  const LikeRecord({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.action,
    required this.createdAt,
  });

  /// `{fromUserId}_{toUserId}` — fromUserId is always the actor's Firebase UID.
  final String id;
  final String fromUserId;
  final String toUserId;
  final SwipeAction action;
  final DateTime createdAt;

  bool get isPositive => action.canCreateMatch;
}
