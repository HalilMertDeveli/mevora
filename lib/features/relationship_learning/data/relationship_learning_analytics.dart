import 'dart:async';

import 'package:mevora/core/analytics/analytics_provider.dart';

/// Daily relationship question events.
///
/// The set id, position and the question's category only. Never the question
/// id with its answer: what someone chose stays between them and Mevora.
class RelationshipLearningAnalytics {
  const RelationshipLearningAnalytics(this._analytics);

  final AnalyticsProvider? _analytics;

  Future<void> _log(String name, Map<String, Object> params) async {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }
    try {
      await analytics.logEvent(name, parameters: params);
    } on Object {
      // Measurement never breaks the experience it measures.
    }
  }

  void shown({required String questionSetId, required String source}) =>
      unawaited(
        _log(AnalyticsEvents.dailyQuestionsShown, {
          'question_set_id': questionSetId,
          'source': source,
        }),
      );

  void resumed({
    required String questionSetId,
    required String source,
    required int answered,
  }) => unawaited(
    _log(AnalyticsEvents.dailyQuestionsResumed, {
      'question_set_id': questionSetId,
      'source': source,
      'answered': answered,
    }),
  );

  void answered({
    required String questionSetId,
    required String category,
    required int position,
  }) => unawaited(
    _log(AnalyticsEvents.dailyQuestionsAnswered, {
      'question_set_id': questionSetId,
      'category': category,
      'position': position,
    }),
  );

  void completed({required String questionSetId, required bool firstSet}) =>
      unawaited(
        _log(AnalyticsEvents.dailyQuestionsCompleted, {
          'question_set_id': questionSetId,
          'first_set': firstSet ? 1 : 0,
        }),
      );

  void skipped({
    required String questionSetId,
    required String source,
    required int answered,
  }) => unawaited(
    _log(AnalyticsEvents.dailyQuestionsSkipped, {
      'question_set_id': questionSetId,
      'source': source,
      'answered': answered,
    }),
  );

  void personalizationSwitched({required bool enabled}) => unawaited(
    _log(
      enabled
          ? AnalyticsEvents.personalizationEnabled
          : AnalyticsEvents.personalizationDisabled,
      const {},
    ),
  );

  void personalizationReset() =>
      unawaited(_log(AnalyticsEvents.personalizationReset, const {}));
}
