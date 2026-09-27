import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
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
  Future<HumorFeedbackResult> skipContent({required String contentId});

  Future<UserHumorProfile> getProfile({bool detailed = false});

  Future<HumorCompatibility> getMatchCompatibility(String matchId);

  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  });
}
