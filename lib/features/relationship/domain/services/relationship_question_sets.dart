import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';

/// Fixed triples from the catalog so two users can actually share a test.
/// Random 3-of-110 would almost never collide.
abstract final class RelationshipQuestionSets {
  static List<List<String>> get sets {
    final ids = RelationshipQuestionCatalog.questions
        .map((question) => question.id)
        .toList(growable: false);
    final out = <List<String>>[];
    for (
      var i = 0;
      i + RelationshipQuestionConfig.questionsPerSession <= ids.length;
      i += RelationshipQuestionConfig.questionsPerSession
    ) {
      out.add(
        ids.sublist(i, i + RelationshipQuestionConfig.questionsPerSession),
      );
    }
    return out;
  }

  static String? setIdFor(List<String> questionIds) {
    final wanted = [...questionIds]..sort();
    for (var i = 0; i < sets.length; i++) {
      final candidate = [...sets[i]]..sort();
      if (_same(wanted, candidate)) {
        return 'set_${i.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }

  static List<RelationshipQuestion>? nextUnanswered(Set<String> answeredIds) {
    final blocked = RelationshipQuestionCatalog.blockedQuestionIds(answeredIds);
    for (final ids in sets) {
      if (ids.every((id) => !blocked.contains(id))) {
        final questions = [
          for (final id in ids) RelationshipQuestionCatalog.byId(id),
        ].whereType<RelationshipQuestion>().toList(growable: false);
        if (questions.length == RelationshipQuestionConfig.questionsPerSession) {
          return questions;
        }
      }
    }
    // Fallback: build a diverse triple from remaining catalog.
    final remaining = RelationshipQuestionCatalog.unanswered(answeredIds);
    if (remaining.length < RelationshipQuestionConfig.questionsPerSession) {
      return null;
    }
    return _pickDiverseTriple(remaining);
  }

  static List<RelationshipQuestion> _pickDiverseTriple(
    List<RelationshipQuestion> pool,
  ) {
    final picked = <RelationshipQuestion>[];
    final usedCategories = <RelationshipContentCategory>{};
    for (final question in pool) {
      if (picked.length >= RelationshipQuestionConfig.questionsPerSession) {
        break;
      }
      if (usedCategories.add(question.category) ||
          usedCategories.length >= RelationshipContentCategory.values.length) {
        picked.add(question);
      }
    }
    while (picked.length < RelationshipQuestionConfig.questionsPerSession &&
        picked.length < pool.length) {
      for (final question in pool) {
        if (!picked.contains(question)) {
          picked.add(question);
          break;
        }
      }
    }
    return picked;
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
