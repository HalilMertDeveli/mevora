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
  /// or advances calibration.
  Future<Result<HumorFeedbackResult>> skipContent({required String contentId});

  Future<Result<UserHumorProfile>> getProfile({bool detailed = false});

  Future<Result<HumorCompatibility>> getMatchCompatibility(String matchId);

  Future<Result<void>> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  });
}
