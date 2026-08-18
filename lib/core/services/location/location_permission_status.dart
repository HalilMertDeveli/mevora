enum LocationPermissionStatus {
  notDetermined,
  granted,
  denied,
  permanentlyDenied,
  restricted,
  serviceDisabled,
  error,
  unknown,
}

extension LocationPermissionStatusX on LocationPermissionStatus {
  bool get isGranted => this == LocationPermissionStatus.granted;

  bool get isDeniedForever =>
      this == LocationPermissionStatus.permanentlyDenied ||
      this == LocationPermissionStatus.restricted;

  bool get canRequestNativeDialog =>
      this == LocationPermissionStatus.notDetermined ||
      this == LocationPermissionStatus.denied;
}
