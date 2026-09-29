import 'dart:async';

import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';

/// Mevora Picks product events.
///
/// Parameters identify the Pick, never the person: [MevoraPick.pickId] is an
/// opaque server hash, and scores are reported only as coarse buckets.
class PicksAnalytics {
  PicksAnalytics(this._analytics);

  final AnalyticsProvider? _analytics;
  final Set<String> _delivered = <String>{};
  final Set<String> _impressions = <String>{};
  final Set<String> _exhausted = <String>{};

  static const String source = 'mevora_picks';

  static String scoreBucket(int score) {
    if (score >= 90) return '90_plus';
    if (score >= 80) return '80_89';
    if (score >= 70) return '70_79';
    if (score >= 60) return '60_69';
    return 'below_60';
  }

  Map<String, Object> _params(MevoraPick pick, int position) => {
    'pick_type': pick.pickType.name,
    'pick_id': pick.pickId,
    'generation_id': pick.generationId,
    'position': position,
    'score_bucket': scoreBucket(pick.overallScore),
    'source': source,
  };

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

  /// Once per Pick per session, when a batch reaches the screen.
  void delivered(List<MevoraPick> picks) {
    for (var i = 0; i < picks.length; i++) {
      if (_delivered.add(picks[i].pickId)) {
        unawaited(_log(AnalyticsEvents.pickDelivered, _params(picks[i], i)));
      }
    }
  }

  /// Once per Pick per session, when its card is first laid out.
  void impression(MevoraPick pick, int position) {
    if (_impressions.add(pick.pickId)) {
      unawaited(_log(AnalyticsEvents.pickImpression, _params(pick, position)));
    }
  }

  void profileOpened(MevoraPick pick, int position) =>
      _log(AnalyticsEvents.pickProfileOpen, _params(pick, position));

  void liked(MevoraPick pick, int position) =>
      _log(AnalyticsEvents.pickLike, _params(pick, position));

  void passed(MevoraPick pick, int position) =>
      _log(AnalyticsEvents.pickPass, _params(pick, position));

  void mutualMatch(MevoraPick pick, int position) =>
      _log(AnalyticsEvents.pickMutualMatch, _params(pick, position));

  /// Once per reason per session: today's finite set has been seen through.
  void exhausted(String reason) {
    if (_exhausted.add(reason)) {
      unawaited(
        _log(AnalyticsEvents.dailyPicksExhausted, {
          'reason': reason,
          'source': source,
        }),
      );
    }
  }
}
