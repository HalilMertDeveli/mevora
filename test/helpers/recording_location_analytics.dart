import 'package:mevora/features/location/data/location_analytics.dart';

class RecordingLocationAnalytics implements LocationAnalytics {
  final List<String> events = [];

  @override
  Future<void> permissionRequested() async {
    events.add('location_permission_requested');
  }

  @override
  Future<void> permissionGranted() async {
    events.add('location_permission_granted');
  }

  @override
  Future<void> permissionDenied() async {
    events.add('location_permission_denied');
  }

  @override
  Future<void> permissionDeniedForever() async {
    events.add('location_permission_denied_forever');
  }

  @override
  Future<void> servicesDisabled() async {
    events.add('location_services_disabled');
  }

  @override
  Future<void> acquired() async {
    events.add('location_acquired');
  }

  @override
  Future<void> error({required String kind}) async {
    events.add('location_error:$kind');
  }
}
