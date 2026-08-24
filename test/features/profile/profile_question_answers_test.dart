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

  test('localization keys exist for question answers profile UI', () {
    expect(tr.questionAnswersTitle, 'Soru & Cevap');
    expect(en.questionAnswersTitle, 'Question & Answers');
    expect(tr.showOnProfile, 'Profilimde göster');
    expect(en.showOnProfile, 'Show on profile');
    expect(tr.seeAllAnswers(3), '3 cevabı daha gör');
    expect(en.seeAllAnswers(3), '3 more answers');
    expect(tr.questionAnswersEmpty, isNotEmpty);
    expect(en.questionAnswersLoadError, isNotEmpty);
  });
}
