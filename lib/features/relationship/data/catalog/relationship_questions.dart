import 'package:mevora/features/relationship/data/catalog/relationship_catalog_entries.dart';

enum RelationshipTopic {
  jealousy,
  trust,
  loyalty,
  communication,
  boundaries,
  socialLife,
  friendship,
  personalSpace,
  futurePlans,
  money,
  flirting,
  exes,
  expectations,
}

/// Content buckets for variety (UI / selection). Matching still uses [topic].
enum RelationshipContentCategory {
  relationship,
  fun,
  dailyLife,
  personality,
  lifestyle,
}

/// How the answer options are framed for a question.
enum RelationshipQuestionType {
  bother,
  acceptable,
  stance,
  timing,
  priority,
  comfort,
  choice,
}

class RelationshipAnswerOption {
  const RelationshipAnswerOption({
    required this.id,
    required this.labelEn,
    required this.labelTr,
    required this.value,
  });

  final String id;
  final String labelEn;
  final String labelTr;

  /// Stable semantic value for compatibility (language-independent).
  final String value;

  String labelFor(String languageCode) {
    return languageCode == 'tr' ? labelTr : labelEn;
  }
}

class RelationshipQuestion {
  const RelationshipQuestion({
    required this.id,
    required this.topic,
    required this.type,
    required this.promptEn,
    required this.promptTr,
    required this.answers,
    this.category = RelationshipContentCategory.relationship,
  });

  final String id;
  final RelationshipTopic topic;
  final RelationshipQuestionType type;
  final RelationshipContentCategory category;
  final String promptEn;
  final String promptTr;
  final List<RelationshipAnswerOption> answers;

  String promptFor(String languageCode) {
    return languageCode == 'tr' ? promptTr : promptEn;
  }

  bool hasAnswer(String answerId) {
    return answers.any((item) => item.id == answerId);
  }

  RelationshipAnswerOption? optionById(String answerId) {
    for (final option in answers) {
      if (option.id == answerId) {
        return option;
      }
    }
    return null;
  }
}

RelationshipQuestion relationshipQuestion(
  int n,
  RelationshipTopic topic,
  String en,
  String tr,
  RelationshipQuestionType type,
  List<RelationshipAnswerOption> answers, {
  RelationshipContentCategory category = RelationshipContentCategory.relationship,
}) {
  return buildCatalogQuestion(
    n,
    topic,
    en,
    tr,
    type,
    answers,
    category: category,
  );
}

/// Public builder for generated catalog entries.
RelationshipQuestion buildCatalogQuestion(
  int n,
  RelationshipTopic topic,
  String en,
  String tr,
  RelationshipQuestionType type,
  List<RelationshipAnswerOption> answers, {
  RelationshipContentCategory category = RelationshipContentCategory.relationship,
}) {
  assert(answers.length == 3, 'Each question must have exactly 3 answers');
  return RelationshipQuestion(
    id: 'rq_${n.toString().padLeft(3, '0')}',
    topic: topic,
    type: type,
    category: category,
    promptEn: en,
    promptTr: tr,
    answers: answers,
  );
}

/// Static catalog. Question text is never written to each user's answers.
abstract final class RelationshipQuestionCatalog {
  static const int version = 3;

  static final List<RelationshipQuestion> questions =
      buildRelationshipCatalogQuestions();

  static RelationshipQuestion? byId(String id) {
    for (final question in questions) {
      if (question.id == id) {
        return question;
      }
    }
    return null;
  }

  static List<RelationshipQuestion> unanswered(Set<String> answeredIds) {
    final blocked = blockedQuestionIds(answeredIds);
    return questions.where((item) => !blocked.contains(item.id)).toList();
  }

  /// Answered ids plus semantic twins (same meaning, different wording).
  static Set<String> blockedQuestionIds(Set<String> answeredIds) {
    final blocked = <String>{...answeredIds};
    for (final id in answeredIds) {
      final answered = byId(id);
      if (answered == null) {
        continue;
      }
      for (final other in questions) {
        if (other.id == answered.id) {
          continue;
        }
        if (areSemanticDuplicates(answered, other)) {
          blocked.add(other.id);
        }
      }
    }
    return blocked;
  }

  static bool areSemanticDuplicates(
    RelationshipQuestion a,
    RelationshipQuestion b,
  ) {
    return semanticKey(a.promptTr) == semanticKey(b.promptTr) ||
        semanticKey(a.promptEn) == semanticKey(b.promptEn);
  }

  /// Token-sorted fingerprint so "Çay mı kahve mi?" ≈ "Kahve mi çay mı?".
  static String semanticKey(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sçğıöşüÇĞİÖŞÜâîûÂÎÛ]', unicode: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tokens = normalized
        .split(' ')
        .where((token) => token.length > 1)
        .where((token) => !_semanticStopwords.contains(token))
        .toList()
      ..sort();
    return tokens.join('|');
  }

  static const Set<String> _semanticStopwords = {
    'mi',
    'mı',
    'mu',
    'mü',
    'midir',
    'mıdır',
    'mudur',
    'müdür',
    'misin',
    'mısın',
    'musun',
    'müsün',
    'ne',
    'nedir',
    'nasil',
    'nasıl',
    'bir',
    'ile',
    'icin',
    'için',
    'veya',
    'yoksa',
    'daha',
    'çok',
    'the',
    'a',
    'an',
    'or',
    'is',
    'are',
    'do',
    'does',
    'you',
    'your',
    'to',
    'of',
    'in',
    'on',
    'for',
    'with',
    'should',
    'would',
    'what',
    'who',
    'which',
  };

  static bool isValidAnswer({
    required String questionId,
    required String answerId,
  }) {
    final question = byId(questionId);
    return question != null && question.hasAnswer(answerId);
  }

  /// Validates catalog integrity. Throws [StateError] on violation.
  static void validateCatalog() {
    final ids = <String>{};
    final answerSignatures = <String>{};
    final semanticKeys = <String, String>{};
    for (final question in questions) {
      if (!ids.add(question.id)) {
        throw StateError('Duplicate question id: ${question.id}');
      }
      if (question.promptTr.trim().isEmpty || question.promptEn.trim().isEmpty) {
        throw StateError('${question.id} has empty prompt');
      }
      if (question.promptTr.length > 90 || question.promptEn.length > 100) {
        throw StateError('${question.id} prompt is too long');
      }
      if (question.answers.length != 3) {
        throw StateError('${question.id} must have 3 answers');
      }
      final answerIds = question.answers.map((item) => item.id).toSet();
      if (answerIds.length != 3) {
        throw StateError('${question.id} has duplicate answer ids');
      }
      final labelsEn = question.answers
          .map((item) => item.labelEn.trim().toLowerCase())
          .toSet();
      final labelsTr = question.answers
          .map((item) => item.labelTr.trim().toLowerCase())
          .toSet();
      if (labelsEn.length != 3 || labelsTr.length != 3) {
        throw StateError('${question.id} has duplicate answer labels');
      }
      for (final answer in question.answers) {
        if (answer.value.trim().isEmpty ||
            answer.labelEn.trim().isEmpty ||
            answer.labelTr.trim().isEmpty) {
          throw StateError('${question.id}/${answer.id} empty field');
        }
        if (answer.labelTr.length > 48 || answer.labelEn.length > 56) {
          throw StateError('${question.id}/${answer.id} answer too long');
        }
      }
      final signature = question.answers
          .map((item) => '${item.labelEn}|${item.labelTr}')
          .join(';;');
      if (!answerSignatures.add(signature)) {
        throw StateError('Duplicate answer set detected for ${question.id}');
      }
      final keyTr = semanticKey(question.promptTr);
      final keyEn = semanticKey(question.promptEn);
      if (keyTr.isNotEmpty) {
        final previous = semanticKeys[keyTr];
        if (previous != null) {
          throw StateError(
            'Semantic duplicate prompts: $previous and ${question.id}',
          );
        }
        semanticKeys[keyTr] = question.id;
      }
      if (keyEn.isNotEmpty && keyEn != keyTr) {
        final previousEn = semanticKeys['en:$keyEn'];
        if (previousEn != null) {
          throw StateError(
            'Semantic duplicate EN prompts: $previousEn and ${question.id}',
          );
        }
        semanticKeys['en:$keyEn'] = question.id;
      }
    }
  }
}
