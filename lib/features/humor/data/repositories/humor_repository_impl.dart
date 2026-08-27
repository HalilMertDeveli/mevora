import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/humor/data/datasources/humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';

class HumorRepositoryImpl implements HumorRepository {
  HumorRepositoryImpl({required HumorDataSource dataSource})
    : _dataSource = dataSource;

  final HumorDataSource _dataSource;

  @override
  Future<Result<HumorFeedPage>> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  }) async {
    try {
      return Success(
        await _dataSource.getFeed(
          languages: languages,
          limit: limit,
          cursor: cursor,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<HumorFeedbackResult>> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool skipped = false,
    bool saved = false,
    bool? swipeUp,
    bool? swipeDown,
  }) async {
    try {
      return Success(
        await _dataSource.submitFeedback(
          contentId: contentId,
          rating: rating,
          dwellMs: dwellMs,
          replayCount: replayCount,
          skipped: skipped,
          saved: saved,
          swipeUp: swipeUp,
          swipeDown: swipeDown,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<UserHumorProfile>> getProfile({bool detailed = false}) async {
    try {
      return Success(await _dataSource.getProfile(detailed: detailed));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<HumorCompatibility>> getMatchCompatibility(
    String matchId,
  ) async {
    try {
      return Success(await _dataSource.getMatchCompatibility(matchId));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) async {
    try {
      await _dataSource.reportContent(
        contentId: contentId,
        reason: reason,
        details: details,
      );
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}
