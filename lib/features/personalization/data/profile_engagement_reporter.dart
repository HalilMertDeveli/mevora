import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';

/// Sends one profile visit's weak engagement to the server.
///
/// Best effort by design: personalization is an enhancement, so a failed or
/// skipped report is dropped silently and never surfaces to the member.
abstract class ProfileEngagementReporter {
  Future<void> report(Map<String, Object> engagement);

  /// The backend reporter when Firebase is up, otherwise a no-op (widget
  /// tests, demo builds without Firebase).
  static ProfileEngagementReporter resolve() {
    if (Firebase.apps.isEmpty) return const NoopProfileEngagementReporter();
    return BackendProfileEngagementReporter(FirebaseFunctionsCallable());
  }
}

class BackendProfileEngagementReporter implements ProfileEngagementReporter {
  BackendProfileEngagementReporter(this._backend);

  final BackendCallable _backend;

  @override
  Future<void> report(Map<String, Object> engagement) async {
    try {
      await _backend.invoke('recordProfileEngagement', engagement);
    } on Object catch (error) {
      debugPrint('profile engagement not recorded: $error');
    }
  }
}

class NoopProfileEngagementReporter implements ProfileEngagementReporter {
  const NoopProfileEngagementReporter();

  @override
  Future<void> report(Map<String, Object> engagement) async {}
}
