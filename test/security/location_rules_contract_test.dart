import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/location/geo_position.dart';
import 'package:mevora/features/location/data/repositories/location_repository_impl.dart';
import 'package:mevora/core/services/location_service.dart';

import '../helpers/fake_location_device.dart';

class _FixedUid implements AuthUidSource {
  _FixedUid(this.currentUid);
  @override
  final String currentUid;
  @override
  Stream<String?> watchUid() => Stream.value(currentUid);
}

void main() {
  test('firestore rules never open the database and hide GPS from others', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    expect(rules.contains('allow read, write: if true'), isFalse);
    expect(rules.contains('match /userLocation/{userId}'), isTrue);
    expect(
      rules.contains('allow read, delete: if isOwner(userId)'),
      isTrue,
    );
    expect(rules.contains('request.resource.data.uid == userId'), isTrue);
    expect(rules.contains("'latitude'"), isTrue);
    expect(rules.contains("'longitude'"), isTrue);
    expect(rules.contains("'location'"), isTrue);
    expect(rules.contains('match /{document=**}'), isTrue);
    expect(rules.contains('allow read, write: if false'), isTrue);
    expect(rules.contains('allow read: if isOwner(userId)'), isTrue);
  });

  test('purchases and boosts are owner-read and client-unwritable', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    expect(rules.contains('match /purchases/{purchaseId}'), isTrue);
    expect(rules.contains('match /boosts/{boostId}'), isTrue);
    expect(rules.contains('match /boostWallet/{docId}'), isTrue);
    expect(rules.contains('match /boostProducts/{productId}'), isTrue);
    expect(rules.contains('allow create, update, delete: if false;'), isTrue);
  });

  test('repository refuses to persist another userId', () async {
    final service = LocationService(
      device: FakeLocationDevice(),
      logger: const AppLogger(environment: AppEnvironment.development),
    );
    final repository = LocationRepositoryImpl(
      locationService: service,
      uidSource: _FixedUid('user-a'),
    );
    final result = await repository.persistOwnerLocation(
      uid: 'user-b',
      position: GeoPosition(
        latitude: 41,
        longitude: 29,
        capturedAt: DateTime.utc(2026, 8, 18),
      ),
    );
    expect(result, isA<Err<void>>());
    expect((result as Err<void>).failure, isA<AuthzFailure>());
  });
}
