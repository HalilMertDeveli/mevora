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

  Future<HumorFeedbackResult> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool skipped = false,
    bool saved = false,
    bool? swipeUp,
    bool? swipeDown,
  });

  Future<UserHumorProfile> getProfile({bool detailed = false});

  Future<HumorCompatibility> getMatchCompatibility(String matchId);

  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  });
}
