import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/features/location/domain/location_update_policy.dart';

void main() {
  const policy = LocationUpdatePolicy();

  GeoPosition at(double lat, double lng, {DateTime? time}) {
    return GeoPosition(
      latitude: lat,
      longitude: lng,
      capturedAt: time ?? DateTime.utc(2026, 8, 18, 12),
    );
  }

  test('writes when no previous location exists', () {
    final next = at(41.0, 29.0);
    expect(
      policy.shouldWrite(next: next, lastPersisted: null, now: next.capturedAt),
      isTrue,
    );
  });

  test('skips a tiny move before the interval elapses', () {
    final last = at(41.0082, 28.9784);
    final next = at(
      41.0083,
      28.9785,
      time: last.capturedAt.add(const Duration(minutes: 5)),
    );
    expect(
      policy.shouldWrite(
        next: next,
        lastPersisted: last,
        now: next.capturedAt,
      ),
      isFalse,
    );
  });

  test('writes after a meaningful move of about 1 km', () {
    final last = at(41.0082, 28.9784);
    final next = at(
      41.02,
      28.99,
      time: last.capturedAt.add(const Duration(minutes: 2)),
    );
    expect(
      policy.shouldWrite(
        next: next,
        lastPersisted: last,
        now: next.capturedAt,
      ),
      isTrue,
    );
  });
}
