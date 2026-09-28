/// Height options in centimeters for profile pickers.
abstract final class HeightCatalog {
  static const minCm = 140;
  static const maxCm = 220;

  static List<int> get options {
    return [
      for (var cm = minCm; cm <= maxCm; cm++) cm,
    ];
  }

  static bool isValid(int? cm) {
    if (cm == null) {
      return false;
    }
    return cm >= minCm && cm <= maxCm;
  }
}
