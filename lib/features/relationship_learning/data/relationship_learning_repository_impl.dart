import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// Calls the daily relationship-question callables and
/// `resetMyPersonalization`.
class RelationshipLearningRepositoryImpl
    implements RelationshipLearningRepository {
  RelationshipLearningRepositoryImpl({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  Future<Result<RelationshipLearningState>> loadState() async {
    try {
      final data = await _backend.invoke(
        'getRelationshipLearningState',
        const {},
      );
      return Success(RelationshipLearningParser.parseState(data));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<DailyAnswerResult>> saveDailyAnswer({
    required String questionSetId,
    required String questionId,
    required int questionVersion,
    required String answerId,
  }) async {
    try {
      final data = await _backend.invoke('saveDailyRelationshipAnswer', {
        'questionSetId': questionSetId,
        'questionId': questionId,
        'questionVersion': questionVersion,
        'answerId': answerId,
      });
      return Success(
        DailyAnswerResult(
          summary: RelationshipLearningParser.parseSummary(data),
          completedTodayNow: data['completedTodayNow'] == true,
          firstSetCompletedNow: data['firstSetCompletedNow'] == true,
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      return Err(_answerFailure(error));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  /// The day turned while the member was answering: the controller reloads
  /// today's set instead of showing an error. Anything else is a plain
  /// "could not save".
  static Failure _answerFailure(FirebaseFunctionsException error) =>
      error.message == learningStaleSetReason
      ? const ValidationFailure(learningStaleSetReason)
      : const UnexpectedFailure('');

  @override
  Future<Result<void>> updateAnswer({
    required String questionId,
    required int questionVersion,
    required String answerId,
  }) async {
    try {
      await _backend.invoke('updateRelationshipAnswer', {
        'questionId': questionId,
        'questionVersion': questionVersion,
        'answerId': answerId,
      });
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<LearningSummary>> skipToday() async {
    try {
      final data = await _backend.invoke(
        'skipTodayRelationshipQuestions',
        const {},
      );
      return Success(RelationshipLearningParser.parseSummary(data));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> skipOnboardingHumor() async {
    try {
      await _backend.invoke('skipOnboardingHumor', const {});
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> resetLearnedPreferences() async {
    try {
      await _backend.invoke('resetMyPersonalization', const {});
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}

/// Parses server payloads. Malformed questions are dropped, never guessed.
abstract final class RelationshipLearningParser {
  static LearningSummary parseSummary(Map<String, dynamic> data) {
    final today = data['today'];
    final nextDay = data['nextDayStartsAtMs'];
    return LearningSummary(
      required: firestoreFlag(data['required']),
      blocksPicks: firestoreFlag(data['blocksPicks']),
      firstSetCompleted: firestoreFlag(data['firstSetCompleted']),
      humorCalibrated: firestoreFlag(data['humorCalibrated']),
      journeyStage: JourneyStage.parse(data['journeyStage']),
      today: today is Map
          ? parseProgress(Map<String, dynamic>.from(today))
          : const DailyProgress(),
      nextDayStartsAt: nextDay is num && nextDay > 0
          ? DateTime.fromMillisecondsSinceEpoch(nextDay.toInt())
          : null,
    );
  }

  static DailyProgress parseProgress(Map<String, dynamic> data) {
    final total = firestoreInt(data['total'], 0);
    return DailyProgress(
      dateKey: data['dateKey'] is String ? data['dateKey'] as String : '',
      questionSetId: data['questionSetId'] is String
          ? data['questionSetId'] as String
          : null,
      total: total,
      answered: firestoreInt(data['answered'], 0).clamp(0, total),
      completed: firestoreFlag(data['completed']),
      skipped: firestoreFlag(data['skipped']),
      canSkip: data['canSkip'] != false,
    );
  }

  /// The `learning` block of a Picks response; unknown when absent.
  static LearningSummary summaryOrUnknown(Object? raw) {
    if (raw is! Map) {
      return LearningSummary.unknown;
    }
    return parseSummary(Map<String, dynamic>.from(raw));
  }

  static RelationshipLearningState parseState(Map<String, dynamic> data) {
    final summary = parseSummary(data);
    final today = data['today'];
    final questions = today is Map
        ? parseQuestions(today['questions'])
        : const <LearningQuestion>[];
    return RelationshipLearningState(
      summary: summary,
      today: DailyQuestionSet(
        dateKey: summary.today.dateKey,
        questionSetId: summary.today.questionSetId ?? '',
        questions: questions,
      ),
      overview: parseOverview(data['overview']),
    );
  }

  static LearningOverview parseOverview(Object? raw) {
    if (raw is! Map) {
      return LearningOverview.empty;
    }
    final data = Map<String, dynamic>.from(raw);
    final categories = <LearningCategoryProgress>[];
    final rawCategories = data['categories'];
    if (rawCategories is List) {
      for (final item in rawCategories.whereType<Map<Object?, Object?>>()) {
        final key = item['key'];
        if (key is! String) {
          continue;
        }
        categories.add(
          LearningCategoryProgress(
            key: key,
            answered: firestoreInt(item['answered'], 0),
            questions: firestoreInt(item['questions'], 0),
            signals: firestoreInt(item['signals'], 0),
            signalsPossible: firestoreInt(item['signalsPossible'], 0),
            progress: _unit(item['progress']),
          ),
        );
      }
    }
    final highlights = <LearningHighlight>[];
    final rawHighlights = data['highlights'];
    if (rawHighlights is List) {
      for (final item in rawHighlights.whereType<Map<Object?, Object?>>()) {
        final text = item['text'];
        final questionId = item['questionId'];
        if (text is! Map || questionId is! String) {
          continue;
        }
        final tr = text['tr'];
        final en = text['en'];
        if (tr is String && en is String) {
          highlights.add(
            LearningHighlight(
              questionId: questionId,
              category: item['category'] is String
                  ? item['category'] as String
                  : '',
              textTr: tr,
              textEn: en,
            ),
          );
        }
      }
    }
    final answered = <AnsweredLearningQuestion>[];
    final rawAnswered = data['answered'];
    if (rawAnswered is List) {
      for (final item in rawAnswered.whereType<Map<Object?, Object?>>()) {
        final map = Map<String, dynamic>.from(item);
        final question = parseQuestion(map);
        if (question == null || !question.isAnswered) {
          continue;
        }
        final at = map['answeredAtMs'];
        answered.add(
          AnsweredLearningQuestion(
            question: question,
            answeredAt: at is num && at > 0
                ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
                : null,
          ),
        );
      }
    }
    final totals = data['totals'];
    return LearningOverview(
      overallProgress: _unit(data['overallProgress']),
      categories: categories,
      totals: totals is Map
          ? LearningTotals(
              thisMonth: firestoreInt(totals['thisMonth'], 0),
              total: firestoreInt(totals['total'], 0),
              completedDays: firestoreInt(totals['completedDays'], 0),
            )
          : const LearningTotals(),
      highlights: highlights,
      answered: answered,
    );
  }

  static double _unit(Object? raw) {
    final value = raw is num ? raw.toDouble() : 0.0;
    return value.isNaN ? 0 : value.clamp(0.0, 1.0);
  }

  static List<LearningQuestion> parseQuestions(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final out = <LearningQuestion>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final question = parseQuestion(Map<String, dynamic>.from(item));
      if (question != null) {
        out.add(question);
      }
    }
    return out;
  }

  static LearningQuestion? parseQuestion(Map<String, dynamic> raw) {
    final id = raw['id'];
    final prompt = raw['prompt'];
    final rawOptions = raw['options'];
    if (id is! String || prompt is! Map || rawOptions is! List) {
      return null;
    }
    final promptTr = prompt['tr'];
    final promptEn = prompt['en'];
    if (promptTr is! String || promptEn is! String) {
      return null;
    }
    final options = <LearningOption>[];
    for (final option in rawOptions) {
      if (option is! Map) {
        continue;
      }
      final optionId = option['id'];
      final label = option['label'];
      if (optionId is! String || label is! Map) {
        continue;
      }
      final tr = label['tr'];
      final en = label['en'];
      if (tr is String && en is String) {
        options.add(LearningOption(id: optionId, labelTr: tr, labelEn: en));
      }
    }
    if (options.length < 2) {
      return null;
    }
    final answer = raw['answerId'];
    final dimension = raw['dimension'] is String
        ? raw['dimension'] as String
        : '';
    return LearningQuestion(
      id: id,
      version: firestoreInt(raw['version'], 1),
      category: raw['category'] is String
          ? raw['category'] as String
          : dimension,
      dimension: dimension,
      answerType: raw['answerType'] == 'scale' ? 'scale' : 'choice',
      promptTr: promptTr,
      promptEn: promptEn,
      options: options,
      answerId: answer is String && options.any((o) => o.id == answer)
          ? answer
          : null,
    );
  }
}
