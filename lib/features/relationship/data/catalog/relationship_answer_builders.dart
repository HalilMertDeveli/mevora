import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';

RelationshipAnswerOption _opt({
  required String id,
  required String labelEn,
  required String labelTr,
  required String value,
}) {
  return RelationshipAnswerOption(
    id: id,
    labelEn: labelEn.trim(),
    labelTr: labelTr.trim(),
    value: value,
  );
}

/// Short, question-specific A/B/C choices. Keeps ids stable for matching.
List<RelationshipAnswerOption> choiceAnswers({
  required String aEn,
  required String aTr,
  required String aValue,
  required String bEn,
  required String bTr,
  required String bValue,
  required String cEn,
  required String cTr,
  required String cValue,
}) {
  return [
    _opt(id: 'a', labelEn: aEn, labelTr: aTr, value: aValue),
    _opt(id: 'b', labelEn: bEn, labelTr: bTr, value: bValue),
    _opt(id: 'c', labelEn: cEn, labelTr: cTr, value: cValue),
  ];
}

/// "Would it bother you if …" — scenario-specific, grammatical labels.
/// Keeps answerId a/b/c + semantic [value] stable for matching.
List<RelationshipAnswerOption> contextualBother({
  required String subjectEn,
  required String subjectTr,
}) {
  final en = _cleanSubject(subjectEn);
  final tr = _cleanSubject(subjectTr);
  return [
    _opt(
      id: 'a',
      labelEn: 'Yes — $en would bother me',
      labelTr: 'Evet — $tr beni rahatsız eder',
      value: 'concern_high',
    ),
    _opt(
      id: 'b',
      labelEn: 'No — $en would not bother me',
      labelTr: 'Hayır — $tr beni rahatsız etmez',
      value: 'concern_low',
    ),
    _opt(
      id: 'c',
      labelEn: 'It depends — how $en is handled matters',
      labelTr: 'Duruma bağlı — $tr konusunda bağlam önemli',
      value: 'conditional',
    ),
  ];
}

/// Acceptability questions — labels reference the specific behaviour.
List<RelationshipAnswerOption> contextualAcceptable({
  required String subjectEn,
  required String subjectTr,
}) {
  final en = _cleanSubject(subjectEn);
  final tr = _cleanSubject(subjectTr);
  return [
    _opt(
      id: 'a',
      labelEn: 'Yes — $en is acceptable to me',
      labelTr: 'Evet — $tr benim için kabul edilebilir',
      value: 'acceptable',
    ),
    _opt(
      id: 'b',
      labelEn: 'No — $en is not acceptable to me',
      labelTr: 'Hayır — $tr benim için kabul edilebilir değil',
      value: 'not_acceptable',
    ),
    _opt(
      id: 'c',
      labelEn: 'It depends on the context around $en',
      labelTr: 'Duruma bağlı — $tr konusunda bağlama göre değişir',
      value: 'conditional',
    ),
  ];
}

/// Opinion / should / is questions — statement form, not raw "Is …?".
List<RelationshipAnswerOption> contextualStance({
  required String statementEn,
  required String statementTr,
}) {
  final en = _cleanSubject(statementEn);
  final tr = _cleanSubject(statementTr);
  return [
    _opt(
      id: 'a',
      labelEn: 'Yes — I agree: $en',
      labelTr: 'Evet — katılıyorum: $tr',
      value: 'agree',
    ),
    _opt(
      id: 'b',
      labelEn: 'No — I disagree: $en',
      labelTr: 'Hayır — katılmıyorum: $tr',
      value: 'disagree',
    ),
    _opt(
      id: 'c',
      labelEn: 'It depends — context around "$en" matters',
      labelTr: 'Duruma bağlı — "$tr" konusunda bağlam önemli',
      value: 'conditional',
    ),
  ];
}

/// Argument timing — question-specific options (rq_012).
List<RelationshipAnswerOption> contextualArgumentTiming() {
  return [
    _opt(
      id: 'a',
      labelEn: 'Talk about it right away during the argument',
      labelTr: 'Tartışma sırasında hemen konuşmak',
      value: 'talk_immediately',
    ),
    _opt(
      id: 'b',
      labelEn: 'Step away, cool down, then talk',
      labelTr: 'Uzaklaşıp sakinleştikten sonra konuşmak',
      value: 'cool_down_first',
    ),
    _opt(
      id: 'c',
      labelEn: 'It depends on how heated the moment feels',
      labelTr: 'O anın ne kadar gergin olduğuna bağlı',
      value: 'conditional',
    ),
  ];
}

/// Weekend priority — question-specific options (rq_030).
List<RelationshipAnswerOption> contextualWeekendPriority() {
  return [
    _opt(
      id: 'a',
      labelEn: 'Yes, most weekends should be spent together',
      labelTr: 'Evet, hafta sonlarının çoğu birlikte geçirilmeli',
      value: 'together_priority',
    ),
    _opt(
      id: 'b',
      labelEn: 'No, individual plans should stay equally important',
      labelTr: 'Hayır, bireysel planlar da eşit derecede önemli kalmalı',
      value: 'individual_priority',
    ),
    _opt(
      id: 'c',
      labelEn: 'It depends on the season and energy we have',
      labelTr: 'Döneme ve enerjimize göre değişir',
      value: 'conditional',
    ),
  ];
}

/// Comfort vs pressure spectrum (rq_059).
List<RelationshipAnswerOption> contextualComfort({
  required String topicEn,
  required String topicTr,
}) {
  final en = _cleanSubject(topicEn);
  final tr = _cleanSubject(topicTr);
  return [
    _opt(
      id: 'a',
      labelEn: '$en feels comforting to me',
      labelTr: '$tr bana güven verir',
      value: 'comfort',
    ),
    _opt(
      id: 'b',
      labelEn: '$en feels like pressure to me',
      labelTr: '$tr bana baskı gibi gelir',
      value: 'pressure',
    ),
    _opt(
      id: 'c',
      labelEn: 'It depends on how openly we agree to it',
      labelTr: 'Ne kadar açıkça karar verdiğimize bağlı',
      value: 'conditional',
    ),
  ];
}

/// Strip leftover second-person crumbs that create "Sen/Ben" soup in TR/EN.
String _cleanSubject(String raw) {
  var value = raw.trim();
  if (value.isEmpty) {
    return value;
  }
  // Turkish leftovers from prompt stripping.
  value = value.replaceFirst(RegExp(r'\s*senin için\s*$', caseSensitive: false), '');
  value = value.replaceFirst(RegExp(r'\s*seni\s*$', caseSensitive: false), '');
  value = value.replaceFirst(RegExp(r'\s*seninle\s*$', caseSensitive: false), '');
  // Collapse whitespace; keep Turkish letters intact (UTF-8).
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Drop trailing punctuation from statements.
  value = value.replaceFirst(RegExp(r'[?.!\s]+$'), '');
  return value.trim();
}
