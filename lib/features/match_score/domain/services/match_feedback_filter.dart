import 'package:mevora/features/match_score/domain/services/match_score_policy.dart';

/// Lightweight insult / PII filter. Server is the source of truth.
abstract final class MatchFeedbackFilter {
  static final RegExp _insults = RegExp(
    [
      r'\bidiot\b',
      r'\bstupid\b',
      r'\bdumb\b',
      r'\bwhore\b',
      r'\bslut\b',
      r'\bbitch\b',
      r'\bfuck(?:ing|er)?\b',
      r'\bshit\b',
      r'\basshole\b',
      r'\bretard(?:ed)?\b',
      'orospu',
      'siktir',
      r'\bamk\b',
      'amına',
      'amina',
      'piç',
      r'\bpic\b',
      'salak',
      r'gerizekal[ıi]',
      'aptal',
      r'\bmal\b',
      'kahpe',
      'yarrak',
    ].join('|'),
    caseSensitive: false,
  );

  static final RegExp _email = RegExp(
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _phone = RegExp(r'(?:\+?\d[\d\s().-]{8,}\d)');

  static String sanitize(String raw) {
    var text = raw.trim();
    if (text.length > MatchScorePolicy.feedbackMaxChars) {
      text = text.substring(0, MatchScorePolicy.feedbackMaxChars);
    }
    text = text.replaceAll(_email, '***');
    text = text.replaceAll(_phone, '***');
    text = text.replaceAll(_insults, '***');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool isAcceptable(String raw) => sanitize(raw).isNotEmpty;
}
