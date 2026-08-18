/// User-selectable discovery radius. Filtering happens on the backend.
enum DiscoveryRadius {
  km5(5),
  km10(10),
  km25(25),
  km50(50),
  km100(100);

  const DiscoveryRadius(this.kilometers);

  final int kilometers;

  static const List<DiscoveryRadius> selectable = values;

  static DiscoveryRadius fromKilometers(int kilometers) {
    return selectable.firstWhere(
      (value) => value.kilometers == kilometers,
      orElse: () => DiscoveryRadius.km25,
    );
  }
}
