import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// Calls the relationship-learning callables and `resetMyPersonalization`.
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
  Future<Result<LearningAnswerResult>> saveAnswer({
    required String questionId,
    required String answerId,
  }) async {
    try {
      final data = await _backend.invoke('saveRelationshipLearningAnswer', {
        'questionId': questionId,
        'answerId': answerId,
      });
      return Success(
        LearningAnswerResult(
          summary: RelationshipLearningParser.parseSummary(data),
          completedInitialNow: data['completedInitialNow'] == true,
          completedRoundNow: data['completedRoundNow'] == true,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> snoozeFollowUp() async {
    try {
      await _backend.invoke('snoozeRelationshipLearningPrompt', const {});
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
    return LearningSummary(
      required: firestoreFlag(data['required']),
      initialTotal: firestoreInt(data['initialTotal'], 15),
      initialAnswered: firestoreInt(data['initialAnswered'], 0),
      initialCompleted: firestoreFlag(data['initialCompleted']),
      blocksPicks: firestoreFlag(data['blocksPicks']),
      progressiveDue: firestoreFlag(data['progressiveDue']),
      followUpSize: firestoreInt(data['followUpSize'], 3),
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
    final initial = data['initial'];
    final followUp = data['progressive'];
    return RelationshipLearningState(
      summary: parseSummary(data),
      initialQuestions: initial is Map
          ? parseQuestions(initial['questions'])
          : const [],
      followUpQuestions: followUp is Map
          ? parseQuestions(followUp['questions'])
          : const [],
    );
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
    return LearningQuestion(
      id: id,
      version: firestoreInt(raw['version'], 1),
      kind: LearningQuestionKind.parse(raw['kind']),
      dimension: raw['dimension'] is String ? raw['dimension'] as String : '',
      promptTr: promptTr,
      promptEn: promptEn,
      options: options,
      answerId: answer is String && options.any((o) => o.id == answer)
          ? answer
          : null,
    );
  }
}
