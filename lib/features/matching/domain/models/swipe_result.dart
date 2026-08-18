import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';

class SwipeResult {
  const SwipeResult({
    required this.action,
    required this.targetUserId,
    this.match,
  });

  final SwipeAction action;
  final String targetUserId;
  final Match? match;

  bool get didMatch => match != null;
}
