import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_display.dart';

void main() {
  group('parsePartnerQuestionAnswersPayload', () {
    test('free matched payload strips answers even if answers array sneaks in', () {
      final snapshot = parsePartnerQuestionAnswersPayload({
        'locked': true,
        'matchRequired': false,
        'premiumRequired': true,
        'isPremium': false,
        'questions': [
          {'questionId': 'rq_001'},
          {'questionId': 'rq_002'},
        ],
        'answers': [
          {'questionId': 'rq_001', 'answerId': 'a', 'isVisible': true},
        ],
      });
      expect(snapshot.premiumRequired, isTrue);
      expect(snapshot.locked, isTrue);
      expect(snapshot.items.length, 2);
      expect(snapshot.items.every((i) => i.answerId.isEmpty), isTrue);
      expect(snapshot.items.every((i) => i.answerLocked), isTrue);
    });

    test('premium matched payload keeps answer ids', () {
      final snapshot = parsePartnerQuestionAnswersPayload({
        'locked': false,
        'matchRequired': false,
        'premiumRequired': false,
        'isPremium': true,
        'questions': [
          {'questionId': 'rq_001'},
        ],
        'answers': [
          {'questionId': 'rq_001', 'answerId': 'b', 'isVisible': true},
        ],
      });
      expect(snapshot.locked, isFalse);
      expect(snapshot.isPremium, isTrue);
      expect(snapshot.items.single.answerId, 'b');
      expect(snapshot.items.single.answerLocked, isFalse);
    });

    test('match-required payload is empty', () {
      final snapshot = parsePartnerQuestionAnswersPayload({
        'locked': true,
        'matchRequired': true,
        'premiumRequired': false,
        'isPremium': false,
        'questions': [],
        'answers': [],
      });
      expect(snapshot.matchRequired, isTrue);
      expect(snapshot.items, isEmpty);
    });
  });

  group('premium-locked sheet defense', () {
    test('locked display never surfaces answer text from a leaked answerId', () {
      const sanitized = ProfileQuestionAnswer(
        questionId: 'rq_001',
        answerId: '',
        isVisible: true,
        answerLocked: true,
      );
      final display = ProfileQuestionAnswerDisplay.resolve(sanitized, 'en');
      expect(display, isNotNull);
      expect(display!.isLocked, isTrue);
      expect(display.answerText, isEmpty);
      expect(display.questionText, isNotEmpty);
    });
  });
}
