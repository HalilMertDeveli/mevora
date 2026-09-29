import 'dart:async';

import 'package:mevora/core/analytics/analytics_provider.dart';

/// Relationship Learning product events.
///
/// Stage, position and the question's dimension only. Never the question id
/// with its answer: what someone chose stays between them and Mevora.
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

  void started({required bool followUp, required String source}) => unawaited(
    _log(
      followUp
          ? AnalyticsEvents.relationshipLearningFollowUpStarted
          : AnalyticsEvents.relationshipLearningStarted,
      {'source': source},
    ),
  );

  void answered({
    required bool followUp,
    required String dimension,
    required int position,
  }) => unawaited(
    _log(AnalyticsEvents.relationshipLearningQuestionAnswered, {
      'stage': followUp ? 'follow_up' : 'initial',
      'dimension': dimension,
      'position': position,
    }),
  );

  void initialCompleted() => unawaited(
    _log(AnalyticsEvents.relationshipLearningInitialCompleted, const {}),
  );

  void followUpCompleted() => unawaited(
    _log(AnalyticsEvents.relationshipLearningFollowUpCompleted, const {}),
  );

  void followUpSnoozed() => unawaited(
    _log(AnalyticsEvents.relationshipLearningFollowUpSnoozed, const {}),
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
