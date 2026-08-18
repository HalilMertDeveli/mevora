enum PermissionStatus {
  granted,
  denied,
  restricted,
  limited,
  permanentlyDenied,
  unknown,
}

extension PermissionStatusX on PermissionStatus {
  /// Photos (and similar) can still be used with limited/selected access.
  bool get isUsable =>
      this == PermissionStatus.granted || this == PermissionStatus.limited;

  bool get isGranted => this == PermissionStatus.granted;

  bool get isLimited => this == PermissionStatus.limited;

  bool get isDenied => this == PermissionStatus.denied;

  bool get isPermanentlyDenied =>
      this == PermissionStatus.permanentlyDenied ||
      this == PermissionStatus.restricted;

  bool get canAskAgain =>
      this == PermissionStatus.denied || this == PermissionStatus.unknown;
}
