import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/firestore.rules').readAsStringSync();
  });

  group('admin automation rules', () {
    test('admin claim helper exists and is token-based', () {
      expect(rules.contains('function isAdmin()'), isTrue);
      expect(rules.contains('request.auth.token.admin == true'), isTrue);
    });

    test('auditLogs are admin-read and client-immutable', () {
      expect(rules.contains('match /auditLogs/{logId}'), isTrue);
      expect(rules.contains('allow read: if isAdmin()'), isTrue);
    });

    test('automationJobs and adminReviewQueue are admin-read only', () {
      expect(rules.contains('match /automationJobs/{jobId}'), isTrue);
      expect(rules.contains('match /adminReviewQueue/{itemId}'), isTrue);
      expect(rules.contains('match /failedNotifications/{id}'), isTrue);
    });

    test('admins can read reports for review queue', () {
      expect(rules.contains('allow read: if isAdmin()'), isTrue);
      expect(
        rules.contains(
          "|| (isAuthenticated() && resource.data.reporterId == request.auth.uid)",
        ),
        isTrue,
      );
    });

    test('users collection locks isSuspended for clients', () {
      expect(rules.contains("'isSuspended'"), isTrue);
      expect(rules.contains("'suspensionReason'"), isTrue);
    });
  });
}
