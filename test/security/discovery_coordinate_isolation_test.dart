import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

class _LeakingBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    return {
      'items': [
        {
          'uid': 'user-b',
          'latitude': 41.0082,
          'longitude': 28.9784,
          'geohash': 'sxk9',
          'distanceLabel': '3.8 km away',
          'distanceKm': 3.8,
          'compatibilityScore': 72,
          'sharedInterests': ['travel'],
          'compatibilityReasons': ['Shared interests'],
          'profile': {
            'displayName': 'Ada',
            'age': 27,
            'latitude': 41.0082,
            'longitude': 28.9784,
            'geohash': 'sxk9',
            'interests': ['travel'],
            'city': 'Istanbul',
          },
        },
      ],
      'nextCursor': null,
    };
  }
}

void main() {
  test('discovery mapper drops leaked coordinates before UI sees them', () async {
    final repository = DiscoveryRepositoryImpl(backend: _LeakingBackend());
    final page = await repository.getCandidates(radius: DiscoveryRadius.km25);
    expect(page, isA<Success<DiscoveryPageResult>>());
    final candidate = page.valueOrNull!.candidates.single;
    expect(candidate.uid, 'user-b');
    expect(candidate.displayName, 'Ada');
    expect(candidate.distanceLabel, '3.8 km away');
    expect(candidate.distanceKm, 3.8);
    final visible = [
      candidate.uid,
      candidate.displayName,
      candidate.distanceLabel,
      candidate.bio,
      candidate.city,
      ...candidate.interests,
      ...candidate.sharedInterests,
      ...candidate.compatibilityReasons,
    ].join(' ');
    expect(visible, isNot(contains('41.0082')));
    expect(visible, isNot(contains('28.9784')));
    expect(visible.toLowerCase(), isNot(contains('latitude')));
    expect(visible.toLowerCase(), isNot(contains('longitude')));
  });

  test('unauthenticated backend errors stay as failures, not coordinates', () async {
    final repository = DiscoveryRepositoryImpl(
      backend: _FailingBackend(const AuthzException('Sign in required.')),
    );
    final page = await repository.getCandidates(radius: DiscoveryRadius.km10);
    expect(page, isA<Err<DiscoveryPageResult>>());
    expect((page as Err<DiscoveryPageResult>).failure, isA<AuthzFailure>());
    expect(page.failureOrNull?.message, isNot(contains('41.')));
  });
}

class _FailingBackend implements BackendCallable {
  _FailingBackend(this.failure);

  final Object failure;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) {
    throw failure;
  }
}
