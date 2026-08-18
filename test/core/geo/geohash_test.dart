import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/geo/geohash.dart';

void main() {
  test('encodes a stable geohash for Istanbul', () {
    final hash = GeoHash.encode(41.0082, 28.9784, precision: 6);
    expect(hash.length, 6);
    expect(GeoHash.encode(41.0082, 28.9784, precision: 6), hash);
  });

  test('distance label never exposes exact meters', () {
    expect(GeoDistance.label(0.4), 'Less than 1 km away');
    expect(GeoDistance.label(2.2), '2 km away');
    expect(GeoDistance.label(150), '100+ km away');
    expect(GeoDistance.labelTr(3.2), '3 km uzakta');
    expect(GeoDistance.labelTr(0.4), "1 km'den yakın");
  });

  test('haversine is roughly 0 for the same point', () {
    expect(
      GeoDistance.km(
        fromLat: 41,
        fromLng: 29,
        toLat: 41,
        toLng: 29,
      ),
      closeTo(0, 0.01),
    );
  });
}
