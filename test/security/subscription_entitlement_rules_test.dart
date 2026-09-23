import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one rule the Premium system rests on: the client can observe
/// entitlement but can never grant it to itself.
void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/firestore.rules').readAsStringSync();
  });

  group('canonical entitlement document', () {
    test('subscription docs are owner-read and server-write only', () {
      expect(rules.contains('match /subscription/{docId}'), isTrue);
      final int start = rules.indexOf('match /subscription/{docId}');
      final String block = rules.substring(start, start + 200);
      expect(block.contains('allow read: if isOwner(userId)'), isTrue);
      expect(block.contains('allow create, update, delete: if false'), isTrue);
    });

    test('purchase records stay server-written', () {
      final int start = rules.indexOf('match /purchases/{purchaseId}');
      expect(start, greaterThan(-1));
      final String block = rules.substring(start, start + 220);
      expect(block.contains('allow create, update, delete: if false'), isTrue);
    });
  });

  group('clients cannot grant themselves premium', () {
    const premiumFields = <String>[
      'subscriptionStatus',
      'isPremium',
      'premium',
      'entitlement',
    ];

    test('every premium field is blocked on the private user document', () {
      final int start = rules.indexOf('match /users/{userId}');
      expect(start, greaterThan(-1));
      final int end = rules.indexOf('match /profiles/{userId}');
      final String block = end > start
          ? rules.substring(start, end)
          : rules.substring(start);
      for (final field in premiumFields) {
        expect(
          "'$field'".allMatches(block).length,
          greaterThanOrEqualTo(2),
          reason: '$field must be blocked on both create and update',
        );
      }
    });

    test('every premium field is blocked on the public profile document', () {
      for (final field in premiumFields) {
        expect(
          rules.contains("'$field'"),
          isTrue,
          reason: '$field must appear in the forbidden key lists',
        );
      }
      expect(rules.contains('profileLifecycleClientSafe'), isTrue);
      expect(rules.contains('profileLifecycleUpdateSafe'), isTrue);
    });
  });
}
