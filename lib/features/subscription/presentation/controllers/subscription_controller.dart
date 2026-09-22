import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

/// Observes Premium entitlement for the whole app.
///
/// Read-only by construction: the client has no way to grant itself Premium.
/// Entitlement is written by the backend into
/// `users/{uid}/subscription/current` and only ever read from here.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({required SubscriptionRepository repository})
    : _repository = repository;

  final SubscriptionRepository _repository;
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
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
