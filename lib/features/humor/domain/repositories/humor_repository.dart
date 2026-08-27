import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';

abstract class HumorRepository {
  Future<Result<HumorFeedPage>> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  });

  Future<Result<HumorFeedbackResult>> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool skipped = false,
    bool saved = false,
    bool? swipeUp,
    bool? swipeDown,
  });

  Future<Result<UserHumorProfile>> getProfile({bool detailed = false});

  Future<Result<HumorCompatibility>> getMatchCompatibility(String matchId);

  Future<Result<void>> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  });
}
