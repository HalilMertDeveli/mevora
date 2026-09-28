import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
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
  }) {
    return _guard(
      'getHumorFeed',
      () => _dataSource.getFeed(
        languages: languages,
        limit: limit,
        cursor: cursor,
      ),
    );
  }

  @override
  Future<Result<HumorFeedbackResult>> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool? swipeUp,
    bool? swipeDown,
  }) {
    return _guard(
      'submitHumorFeedback',
      () => _dataSource.submitFeedback(
        contentId: contentId,
        rating: rating,
        dwellMs: dwellMs,
        replayCount: replayCount,
        swipeUp: swipeUp,
        swipeDown: swipeDown,
      ),
    );
  }

  @override
  Future<Result<HumorFeedbackResult>> skipContent({
    required String contentId,
    String? skipReason,
  }) {
    return _guard(
      'submitHumorFeedback',
      () =>
          _dataSource.skipContent(contentId: contentId, skipReason: skipReason),
    );
  }

  @override
  Future<Result<UserHumorProfile>> getProfile({bool detailed = false}) {
    return _guard(
      'getHumorProfile',
      () => _dataSource.getProfile(detailed: detailed),
    );
  }

  @override
  Future<Result<HumorCompatibility>> getMatchCompatibility(String matchId) {
    return _guard(
      'getMatchHumorCompatibility',
      () => _dataSource.getMatchCompatibility(matchId),
    );
  }

  @override
  Future<Result<void>> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) {
    return _guard(
      'reportHumorContent',
      () => _dataSource.reportContent(
        contentId: contentId,
        reason: reason,
        details: details,
      ),
    );
  }

  /// Runs one humor call and turns whatever it throws into a [Failure].
  ///
  /// Callable errors keep their meaning here instead of all collapsing into
  /// "something went wrong": an offline device, an expired session and a
  /// backend fault need different words, and QA needs to see which one
  /// happened. The shared callable wrapper is left alone on purpose — other
  /// features catch the raw exception type.
  Future<Result<T>> _guard<T>(
    String callable,
    Future<T> Function() action,
  ) async {
    try {
      return Success(await action());
    } on FirebaseFunctionsException catch (error) {
      _debug(callable, error.code, error.message);
      return Err(_mapHumorCallableError(error.code, error.message));
    } on Object catch (error) {
      _debug(callable, error.runtimeType.toString(), null);
      return Err(FailureMapper.from(error));
    }
  }

  void _debug(String callable, String code, String? message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint(
      '[HUMOR] $callable failed: $code${message == null ? '' : ' ($message)'}',
    );
  }
}

/// Maps a Cloud Functions error code onto the app's existing [Failure] types.
Failure _mapHumorCallableError(String code, [String? message]) {
  final detail = message == null || message.isEmpty ? code : '$code: $message';
  switch (code) {
    case 'unavailable':
    case 'deadline-exceeded':
      return NetworkFailure(detail);
    case 'unauthenticated':
      return AuthFailure(
        detail,
        kind: AuthErrorKind.sessionExpired,
        code: code,
      );
    case 'permission-denied':
      return AuthzFailure(detail);
    case 'not-found':
      return NotFoundFailure(detail);
    default:
      return UnexpectedFailure(detail);
  }
}
