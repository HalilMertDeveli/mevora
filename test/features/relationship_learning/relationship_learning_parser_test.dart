import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship_learning/data/relationship_learning_repository_impl.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';

Map<String, dynamic> _question(String id, {Object? answerId}) => {
  'id': id,
  'version': 2,
  'kind': 'importance',
  'dimension': 'humor',
  'prompt': {
    'tr': 'Mizah ne kadar önemli?',
    'en': 'How much does humor matter?',
  },
  'options': [
    {
      'id': 'a',
      'label': {'tr': 'Çok', 'en': 'A lot'},
    },
    {
      'id': 'b',
      'label': {'tr': 'Biraz', 'en': 'Somewhat'},
    },
  ],
  'answerId': answerId,
};

void main() {
  test('parses the state, keeping saved answers for resume', () {
    final state = RelationshipLearningParser.parseState({
      'required': true,
      'initialTotal': 15,
      'initialAnswered': 1,
      'initialCompleted': false,
      'blocksPicks': true,
      'progressiveDue': false,
      'followUpSize': 3,
      'initial': {
        'questions': [_question('rl_a', answerId: 'b'), _question('rl_b')],
      },
      'progressive': {'questions': <Object>[]},
    });
    expect(state.summary.required, isTrue);
    expect(state.summary.blocksPicks, isTrue);
    expect(state.summary.invitesInitial, isFalse);
    expect(state.initialQuestions, hasLength(2));
    final first = state.initialQuestions.first;
    expect(first.answerId, 'b');
    expect(first.version, 2);
    expect(first.kind, LearningQuestionKind.importance);
    expect(first.promptFor('tr'), 'Mizah ne kadar önemli?');
    expect(first.options.last.labelFor('en'), 'Somewhat');
    expect(state.followUpQuestions, isEmpty);
  });

  test('drops malformed questions and foreign answers instead of guessing', () {
    final questions = RelationshipLearningParser.parseQuestions([
      _question('rl_ok', answerId: 'z'),
      {'id': 'rl_no_prompt', 'options': <Object>[]},
      {'id': 7, 'prompt': <String, Object>{}, 'options': <Object>[]},
      'garbage',
      {
        ..._question('rl_one_option'),
        'options': [
          {
            'id': 'a',
            'label': {'tr': 'x', 'en': 'x'},
          },
        ],
      },
    ]);
    expect(questions.map((q) => q.id), ['rl_ok']);
    expect(questions.single.answerId, isNull);
  });

  test('a Picks response without a learning block never blocks or prompts', () {
    final summary = RelationshipLearningParser.summaryOrUnknown(null);
    expect(summary.blocksPicks, isFalse);
    expect(summary.invitesInitial, isFalse);
    expect(summary.progressiveDue, isFalse);
  });
}
