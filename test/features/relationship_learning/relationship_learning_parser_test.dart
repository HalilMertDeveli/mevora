import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship_learning/data/relationship_learning_repository_impl.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';

Map<String, dynamic> _question(String id, {Object? answerId}) => {
  'id': id,
  'version': 2,
  'answerType': 'scale',
  'category': 'humor',
  'dimension': 'humor',
  'prompt': {
    'tr': 'Mizah ne kadar önemli?',
    'en': 'How much does humor matter?',
  },
  'options': [
    {
      'id': 'important',
      'label': {'tr': 'Önemli', 'en': 'Important'},
    },
    {
      'id': 'not_important',
      'label': {'tr': 'Önemli değil', 'en': 'Not important'},
    },
  ],
  'answerId': answerId,
};

void main() {
  test("parses today's set, keeping today's answers for resume", () {
    final state = RelationshipLearningParser.parseState({
      'required': true,
      'blocksPicks': true,
      'firstSetCompleted': false,
      'journeyStage': 'daily',
      'nextDayStartsAtMs': 1_790_000_000_000,
      'today': {
        'dateKey': '2026-09-29',
        'questionSetId': 'daily-2026-09-29-s1',
        'total': 10,
        'answered': 1,
        'completed': false,
        'skipped': false,
        'canSkip': false,
        'questions': [
          _question('relationship_humor_importance_v2', answerId: 'important'),
          _question('relationship_b_v2'),
        ],
      },
    });
    expect(state.summary.required, isTrue);
    expect(state.summary.blocksPicks, isTrue);
    expect(state.summary.journeyStage, JourneyStage.daily);
    expect(state.summary.today.answered, 1);
    expect(state.summary.today.canSkip, isFalse);
    expect(state.summary.invitesToday, isFalse, reason: 'the gate shows');
    expect(state.summary.nextDayStartsAt, isNotNull);
    expect(state.today.questionSetId, 'daily-2026-09-29-s1');
    expect(state.today.dateKey, '2026-09-29');
    expect(state.today.questions, hasLength(2));
    final first = state.today.questions.first;
    expect(first.answerId, 'important');
    expect(first.version, 2);
    expect(first.answerType, 'scale');
    expect(first.category, 'humor');
    expect(first.promptFor('tr'), 'Mizah ne kadar önemli?');
    expect(first.options.last.labelFor('en'), 'Not important');
  });

  test('drops malformed questions and foreign answers instead of guessing', () {
    final questions = RelationshipLearningParser.parseQuestions([
      _question('relationship_ok_v1', answerId: 'z'),
      {'id': 'relationship_no_prompt_v1', 'options': <Object>[]},
      {'id': 7, 'prompt': <String, Object>{}, 'options': <Object>[]},
      'garbage',
      {
        ..._question('relationship_one_option_v1'),
        'options': [
          {
            'id': 'a',
            'label': {'tr': 'x', 'en': 'x'},
          },
        ],
      },
    ]);
    expect(questions.map((q) => q.id), ['relationship_ok_v1']);
    expect(questions.single.answerId, isNull);
  });

  test('a Picks response without a learning block never blocks or prompts', () {
    final summary = RelationshipLearningParser.summaryOrUnknown(null);
    expect(summary.blocksPicks, isFalse);
    expect(summary.invitesToday, isFalse);
  });

  test('an unfinished, unskipped day invites; a skipped one does not', () {
    LearningSummary parse(Map<String, dynamic> today) =>
        RelationshipLearningParser.summaryOrUnknown({'today': today});
    expect(parse({'answered': 3, 'total': 10}).invitesToday, isTrue);
    expect(parse({'skipped': true}).invitesToday, isFalse);
    expect(parse({'completed': true}).invitesToday, isFalse);
    expect(
      parse({'answered': 99, 'total': 10}).today.answered,
      10,
      reason: 'clamped',
    );
  });
}
