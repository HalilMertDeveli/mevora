import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/relationship/data/datasources/relationship_data_source.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

class RelationshipRepositoryImpl implements RelationshipRepository {
  RelationshipRepositoryImpl({required RelationshipDataSource dataSource})
    : _dataSource = dataSource;

  final RelationshipDataSource _dataSource;

  @override
  Future<Result<RelationshipAnswerSnapshot>> getAnswered() {
    return _guard(_dataSource.getAnswered);
  }

  @override
  Future<Result<RelationshipAnswerSnapshot>> saveAnswer({
    required String questionId,
    required String answerId,
  }) {
    return _guard(
      () => _dataSource.saveAnswer(questionId: questionId, answerId: answerId),
    );
  }

  @override
  Future<Result<RelationshipAnswerSnapshot>> dismissOffer({
    bool matchTaken = false,
  }) {
    return _guard(() => _dataSource.dismissOffer(matchTaken: matchTaken));
  }

  @override
  Future<Result<List<RelationshipMatchSuggestion>>> completeTest({
    required List<String> questionIds,
  }) {
    return _guard(() => _dataSource.completeTest(questionIds: questionIds));
  }

  @override
  Future<Result<List<RelationshipMatchSuggestion>>> getSuggestions() {
    return _guard(_dataSource.getSuggestions);
  }

  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on FirebaseFunctionsException catch (error) {
      _debug('FirebaseFunctionsException ${error.code}: ${error.message}');
      return Err(UnexpectedFailure('${error.code}: ${error.message}'));
    } on FirebaseException catch (error) {
      _debug('FirebaseException ${error.code}: ${error.message}');
      return Err(UnexpectedFailure('${error.code}: ${error.message}'));
    } on Object catch (error) {
      _debug('$error');
      return Err(FailureMapper.from(error));
    }
  }

  void _debug(String message) {
    if (kDebugMode) {
      debugPrint('[RELATIONSHIP_DEBUG] $message');
    }
  }
}
