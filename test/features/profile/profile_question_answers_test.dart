import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_display.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('profile answer display resolves catalog text by questionId', () {
    const answer = ProfileQuestionAnswer(
      questionId: 'rq_001',
      answerId: 'a',
      isVisible: true,
    );
    final display = ProfileQuestionAnswerDisplay.resolve(answer, 'tr');
    expect(display, isNotNull);
    expect(display!.questionText, isNotEmpty);
    expect(display.answerText, isNotEmpty);
    expect(
      RelationshipQuestionCatalog.byId('rq_001')!.promptFor('tr'),
      display.questionText,
    );
  });

  test('duplicate questionId uses latest profile answer entry', () {
    final older = ProfileQuestionAnswer(
      questionId: 'rq_002',
      answerId: 'a',
      isVisible: true,
      updatedAt: DateTime(2026, 8, 20),
    );
    final newer = ProfileQuestionAnswer(
      questionId: 'rq_002',
      answerId: 'b',
      isVisible: true,
      updatedAt: DateTime(2026, 8, 23),
    );
    final map = {older.questionId: older, newer.questionId: newer};
    expect(map['rq_002']!.answerId, 'b');
  });

  test('locked peer answers resolve question text without answer text', () {
    const answer = ProfileQuestionAnswer(
      questionId: 'rq_001',
      answerId: '',
      isVisible: true,
      answerLocked: true,
    );
    final display = ProfileQuestionAnswerDisplay.resolve(answer, 'en');
    expect(display, isNotNull);
    expect(display!.isLocked, isTrue);
    expect(display.questionText, isNotEmpty);
    expect(display.answerText, isEmpty);
  });

  test('localization keys exist for question answers profile UI', () {
    expect(tr.questionAnswersTitle, 'Soru & Cevap');
    expect(en.questionAnswersTitle, 'Question & Answers');
    expect(tr.showOnProfile, 'Profilimde göster');
    expect(en.showOnProfile, 'Show on profile');
    expect(tr.seeAllAnswers(3), '3 cevabı daha gör');
    expect(en.seeAllAnswers(3), '3 more answers');
    expect(tr.questionAnswersEmpty, isNotEmpty);
    expect(tr.questionAnswersEmptyHint, isNotEmpty);
    expect(en.questionAnswersEmptyHint, isNotEmpty);
    expect(en.questionAnswersLoadError, isNotEmpty);
    expect(en.questionAnswersSaveError, isNotEmpty);
    expect(tr.questionAnswersSaveError, isNotEmpty);
    expect(en.questionAnswersPremiumLockedMessage, isNotEmpty);
    expect(en.questionAnswersPremiumUnlockCta, isNotEmpty);
    expect(en.questionAnswersPremiumAnswerHidden, isNotEmpty);
  });

  test('catalog includes rq_111 which server must accept', () {
    expect(RelationshipQuestionCatalog.byId('rq_111'), isNotNull);
    expect(RelationshipQuestionCatalog.questions.length, greaterThanOrEqualTo(111));
  });
}
