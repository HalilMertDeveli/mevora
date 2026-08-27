import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_core/firebase_core.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/data/datasources/profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';

class ProfileQuestionAnswerRepositoryImpl
    implements ProfileQuestionAnswerRepository {
  ProfileQuestionAnswerRepositoryImpl({
    required ProfileQuestionAnswerDataSource dataSource,
  }) : _dataSource = dataSource;

  final ProfileQuestionAnswerDataSource _dataSource;

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) {
    return _dataSource.watchAnswers(uid, visibleOnly: visibleOnly);
  }

  @override
  Future<Result<PartnerQuestionAnswersSnapshot>> fetchPartnerAnswers(
    String partnerUid,
  ) {
    return _guardValue(() => _dataSource.fetchPartnerAnswers(partnerUid));
  }

  @override
  Future<Result<void>> syncFromMatching() {
    return _guard(_dataSource.syncFromMatching);
  }

  @override
  Future<Result<void>> setVisibility({
    required String questionId,
    required bool isVisible,
  }) {
    return _guard(
      () => _dataSource.setVisibility(
        questionId: questionId,
        isVisible: isVisible,
      ),
    );
  }

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } on FirebaseFunctionsException catch (error) {
      return Err(UnexpectedFailure('${error.code}: ${error.message}'));
    } on FirebaseException catch (error) {
      return Err(UnexpectedFailure('${error.code}: ${error.message}'));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  Future<Result<T>> _guardValue<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on FirebaseFunctionsException catch (error) {
      return Err(UnexpectedFailure('${error.code}: ${error.message}'));
    } on FirebaseException catch (error) {
      return Err(UnexpectedFailure('${error.code}: ${error.message}'));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}
