import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/geo/distance_calculator.dart';

void main() {
  group('DistanceCalculator.calculate', () {
    test('same location is zero', () {
      expect(DistanceCalculator.calculate(41.0082, 28.9784, 41.0082, 28.9784), 0);
    });

    test('zero coordinates are zero', () {
      expect(DistanceCalculator.calculate(0, 0, 0, 0), 0);
    });

    test('nearby points are under 2 km', () {
      final km = DistanceCalculator.calculate(
        41.0082,
        28.9784,
        41.015,
        28.985,
      );
      expect(km, greaterThan(0));
      expect(km, lessThan(2));
    });

    test('Istanbul and Ankara are hundreds of kilometers apart', () {
      final km = DistanceCalculator.calculate(
        41.0082,
        28.9784,
        39.9334,
        32.8597,
      );
      expect(km, inInclusiveRange(300, 450));
    });

    test('invalid coordinates return NaN', () {
      expect(DistanceCalculator.calculate(91, 0, 0, 0).isNaN, isTrue);
      expect(DistanceCalculator.calculate(0, 181, 0, 0).isNaN, isTrue);
    });
  });

  group('DistanceCalculator.format', () {
    test('formats sub-kilometer distances in meters', () {
      expect(DistanceCalculator.format(0.4), '400 m');
    });

    test('formats kilometers with one decimal when needed', () {
      expect(DistanceCalculator.format(1.2), '1.2 km');
    });

    test('formats whole kilometers without a trailing decimal', () {
      expect(DistanceCalculator.format(5), '5 km');
    });
  });
}
