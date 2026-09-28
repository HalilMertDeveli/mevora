import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

/// Observes Premium entitlement for the whole app.
///
/// Read-only by construction: the client has no way to grant itself Premium.
/// Entitlement is written by the backend into
/// `users/{uid}/subscription/current` and only ever read from here.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({
    required SubscriptionRepository repository,
    AnalyticsProvider? analytics,
  }) : _repository = repository,
       _analytics = analytics;

  final SubscriptionRepository _repository;
  final AnalyticsProvider? _analytics;
  StreamSubscription<PremiumStatus>? _subscription;

  PremiumStatus _status = PremiumStatus.free;
  bool _started = false;

  PremiumStatus get status => _status;

  bool get isPremium => _status.isPremium;

  /// Starts observing. Safe to call more than once.
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _subscription = _repository.watch().listen(
      _onStatus,
      onError: (Object _) => _onStatus(PremiumStatus.free),
    );
  }

  void _onStatus(PremiumStatus status) {
    if (identical(status, _status)) {
      return;
    }
    final wasPremium = _status.isPremium;
    _status = status;
    // Only when access actually crosses the line. Every renewal and every
    // lifecycle nuance also arrives here, and reporting each one would drown
    // the event that matters: Premium was gained, or Premium was lost.
    if (wasPremium != status.isPremium) {
      final analytics = _analytics;
      if (analytics != null) {
        unawaited(
          analytics
              .logEvent(
                AnalyticsEvents.premiumEntitlementChanged,
                parameters: <String, Object>{'is_premium': status.isPremium},
              )
              .catchError((Object _) {}),
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
