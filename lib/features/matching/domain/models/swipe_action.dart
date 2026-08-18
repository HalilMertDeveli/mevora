enum SwipeAction { like, pass, superLike }

extension SwipeActionX on SwipeAction {
  /// Domain wire value. Data sources persist this string.
  String get wireValue => switch (this) {
    SwipeAction.like => 'like',
    SwipeAction.pass => 'pass',
    SwipeAction.superLike => 'superLike',
  };

  String get firestoreValue => wireValue;

  bool get canCreateMatch =>
      this == SwipeAction.like || this == SwipeAction.superLike;

  static SwipeAction fromWire(String value) {
    return switch (value) {
      'pass' => SwipeAction.pass,
      'superLike' => SwipeAction.superLike,
      _ => SwipeAction.like,
    };
  }

  static SwipeAction fromFirestore(String value) => fromWire(value);
}
