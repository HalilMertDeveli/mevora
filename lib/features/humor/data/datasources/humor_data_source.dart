import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';

/// Remote humor API. Implementations talk to Cloud Functions or in-memory mocks.
abstract class HumorDataSource {
  Future<HumorFeedPage> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  });

  /// Rate [contentId]. Rating the same content again replaces the earlier
  /// rating server-side instead of adding a second step.
  Future<HumorFeedbackResult> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool? swipeUp,
    bool? swipeDown,
  });

  /// Move past [contentId] without rating it. Never changes the profile,
  /// the interaction count or calibration progress; it only keeps the content
  /// out of the user's feed.
  ///
  /// [skipReason] (see `HumorSkipReason`) says why; `null` sends none.
  Future<HumorFeedbackResult> skipContent({
    required String contentId,
    String? skipReason,
  });

  Future<UserHumorProfile> getProfile({bool detailed = false});

  Future<HumorCompatibility> getMatchCompatibility(String matchId);

  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  });

  /// Today's "Bugünün Mizah Turu" (`getDailyHumorSet`).
  Future<HumorDailySet> getDailySet();

  /// Rate the daily slot holding [contentId] on [dayId]. Idempotent: the same
  /// slot again returns the same progress with `alreadyAnswered`.
  Future<HumorDailyProgress> submitDailyResponse({
    required String dayId,
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
  });

  /// Pass the daily slot holding [contentId] because its media could not be
  /// played (`skipReason: media_failed`) — the only skip the tour has.
  Future<HumorDailyProgress> skipDailyItem({
    required String dayId,
    required String contentId,
  });
}
