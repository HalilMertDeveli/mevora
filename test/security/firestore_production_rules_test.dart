import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/firestore.rules').readAsStringSync();
  });

  group('profile lifecycle', () {
    test('clients cannot self-enable discoverability or completion flags', () {
      expect(rules.contains('profileLifecycleClientSafe'), isTrue);
      expect(rules.contains('profileLifecycleUpdateSafe'), isTrue);
      expect(rules.contains("'isDiscoverable'"), isTrue);
      expect(rules.contains("'profileCompleted'"), isTrue);
      expect(rules.contains('birthDateUnchanged'), isTrue);
      expect(rules.contains('ageUnchanged'), isTrue);
    });

    test('clients cannot write moderation or admin-only profile fields', () {
      expect(rules.contains("'profileModerationStatus'"), isTrue);
      expect(rules.contains("'isVerified'"), isTrue);
      expect(rules.contains("'isAdmin'"), isTrue);
      expect(rules.contains("'subscriptionStatus'"), isTrue);
      expect(rules.contains("'boostStatus'"), isTrue);
    });

    test('verification subcollection is read-only for clients', () {
      expect(rules.contains('match /verification/{docId}'), isTrue);
      expect(rules.contains('allow create, update, delete: if false'), isTrue);
    });
  });

  group('block and report safety', () {
    test('message writes respect top-level blocks collection', () {
      expect(rules.contains('function isBlockedPair(a, b)'), isTrue);
      expect(rules.contains(r"blocks/$(a + '_' + b)"), isTrue);
      expect(rules.contains(r"blocks/$(b + '_' + a)"), isTrue);
    });

    test('reports are create-only for the reporter and not publicly readable', () {
      expect(rules.contains('match /reports/{reportId}'), isTrue);
      expect(rules.contains('resource.data.reporterId == request.auth.uid'), isTrue);
      expect(rules.contains('request.resource.data.status == \'open\''), isTrue);
      expect(rules.contains('allow update, delete: if false'), isTrue);
    });
  });

  group('server-only collections', () {
    test('message rate limits and purchases stay server controlled', () {
      expect(rules.contains('match /rateLimits/{docId}'), isTrue);
      expect(rules.contains('match /purchases/{purchaseId}'), isTrue);
      expect(rules.contains('allow create, update, delete: if false;'), isTrue);
    });
  });
}
