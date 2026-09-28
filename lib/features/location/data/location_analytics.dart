import 'package:mevora/core/analytics/analytics_provider.dart';

/// Location product events. Never attach lat/lng or geohash.
abstract class LocationAnalytics {
  Future<void> permissionRequested();

  Future<void> permissionGranted();

  Future<void> permissionDenied();

  Future<void> permissionDeniedForever();

  Future<void> servicesDisabled();

  Future<void> acquired();

  Future<void> error({required String kind});
}

class NoOpLocationAnalytics implements LocationAnalytics {
  const NoOpLocationAnalytics();

  @override
  Future<void> permissionRequested() async {}

  @override
  Future<void> permissionGranted() async {}

  @override
  Future<void> permissionDenied() async {}

  @override
  Future<void> permissionDeniedForever() async {}

  @override
  Future<void> servicesDisabled() async {}

  @override
  Future<void> acquired() async {}

  @override
  Future<void> error({required String kind}) async {}
}

class AnalyticsLocationAnalytics implements LocationAnalytics {
  AnalyticsLocationAnalytics(this._analytics);

  final AnalyticsProvider _analytics;

  Future<void> _log(String name, {Map<String, Object>? parameters}) {
    return _analytics.logEvent(name, parameters: parameters);
  }

  @override
  Future<void> permissionRequested() {
    return _log(AnalyticsEvents.locationPermissionRequested);
  }

  @override
  Future<void> permissionGranted() {
    return _log(AnalyticsEvents.locationPermissionGranted);
  }

  @override
  Future<void> permissionDenied() {
    return _log(AnalyticsEvents.locationPermissionDenied);
  }

  @override
  Future<void> permissionDeniedForever() {
    return _log(AnalyticsEvents.locationPermissionDeniedForever);
  }

  @override
  Future<void> servicesDisabled() {
    return _log(AnalyticsEvents.locationServicesDisabled);
  }

  @override
  Future<void> acquired() {
    return _log(AnalyticsEvents.locationAcquired);
  }

  @override
  Future<void> error({required String kind}) {
    return _log(
      AnalyticsEvents.locationError,
      parameters: {'kind': kind},
    );
  }
}
