import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';

/// Why an item was passed without a rating (`submitHumorFeedback.skipReason`).
abstract final class HumorSkipReason {
  /// The user chose to skip it.
  static const user = 'user';

  /// Its media could not be played, so the user never saw it. Never a rating
  /// and never counted toward calibration.
  static const mediaFailed = 'media_failed';
}

abstract class HumorRepository {
  Future<Result<HumorFeedPage>> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  });

  /// Rate a piece of content. Changing an earlier rating replaces it on the
  /// server; it never counts as a second interaction.
  Future<Result<HumorFeedbackResult>> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool? swipeUp,
    bool? swipeDown,
  });

  /// Move past a piece of content without rating it. Never trains the profile
  /// or advances calibration. [skipReason] is one of [HumorSkipReason]; left
  /// out, the server treats it as the user's own skip.
  Future<Result<HumorFeedbackResult>> skipContent({
    required String contentId,
    String? skipReason,
  });

  Future<Result<UserHumorProfile>> getProfile({bool detailed = false});

  Future<Result<HumorCompatibility>> getMatchCompatibility(String matchId);

  Future<Result<void>> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  });

  /// Today's "Bugünün Mizah Turu": ready, locked or not ready yet.
  Future<Result<HumorDailySet>> getDailySet();

  /// Rate one daily slot. A refusal because the day, slot or eligibility
  /// changed arrives as [HumorDailyStale] (reload the set); a network or
  /// other error as an `Err` (keep the item, allow a retry).
  Future<Result<HumorDailySubmitOutcome>> submitDailyResponse({
    required String dayId,
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
  });

  /// Pass one daily slot whose media could not be played (`media_failed`).
  /// Same outcomes as [submitDailyResponse].
  Future<Result<HumorDailySubmitOutcome>> skipDailyItem({
    required String dayId,
    required String contentId,
  });
}
