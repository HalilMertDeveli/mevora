import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/errors/social_error_mapper.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/matching/domain/models/swipe_result.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

class RecordSwipeUseCase {
  const RecordSwipeUseCase(this._likes);

  final LikeRepository _likes;

  Future<Result<SwipeResult>> call({
    required String targetUserId,
    required SwipeAction action,
  }) async {
    try {
      final result = await _likes.recordSwipe(
        targetUserId: targetUserId,
        action: action.wireValue,
      );
      return Success(
        SwipeResult(
          action: action,
          targetUserId: targetUserId,
          match: result.match,
        ),
      );
    } on Object catch (error) {
      return Err(SocialErrorMapper.map(error));
    }
  }
}

class WatchMatchesUseCase {
  const WatchMatchesUseCase(this._matches);

  final MatchRepository _matches;

  Stream<List<MatchListItem>> call(String uid) => _matches.watchMatches(uid);
}
