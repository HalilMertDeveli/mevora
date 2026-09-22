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

    test('users cannot self-set isSuspended or suspension metadata', () {
      expect(
        rules.contains(
          "request.resource.data.get('isSuspended', resource.data.get('isSuspended', false))",
        ),
        isTrue,
      );
      expect(rules.contains("'suspensionReason'"), isTrue);
    });

    test('verification subcollection is read-only for clients', () {
      expect(rules.contains('match /verification/{docId}'), isTrue);
      expect(rules.contains('allow create, update, delete: if false'), isTrue);
    });

    test('profile question answers are readable only when visible to others', () {
      expect(rules.contains('match /questionAnswers/{questionId}'), isTrue);
      expect(rules.contains('function hasActiveMatchWith(otherUid)'), isTrue);
      expect(rules.contains('function canonicalMatchId(uidA, uidB)'), isTrue);
      // Legacy docs omit isVisible — default true so matched viewers still see them.
      expect(
        rules.contains("resource.data.get('isVisible', true) == true"),
        isTrue,
      );
    });
  });

  group('block and report safety', () {
    test('message writes respect top-level blocks collection', () {
      expect(rules.contains('function isBlockedPair(a, b)'), isTrue);
      expect(rules.contains(r"blocks/$(a + '_' + b)"), isTrue);
      expect(rules.contains(r"blocks/$(b + '_' + a)"), isTrue);
    });

    test('reports are CF-only create and not publicly readable', () {
      expect(rules.contains('match /reports/{reportId}'), isTrue);
      expect(rules.contains('resource.data.reporterId == request.auth.uid'), isTrue);
      expect(rules.contains('Reports are created only by Cloud Functions'), isTrue);
      expect(rules.contains('allow create, update, delete: if false'), isTrue);
      expect(rules.contains('function isAdmin()'), isTrue);
    });

    test('match meta writes are limited to typing indicators', () {
      expect(rules.contains("docId == 'typing'"), isTrue);
      expect(rules.contains('typingMetaWriteValid'), isTrue);
    });

    test('new messages require E2EE ciphertext and owned media paths', () {
      expect(rules.contains('messageCreatePayloadValid'), isTrue);
      expect(rules.contains('messageEncryptedFieldsValid'), isTrue);
      expect(rules.contains('chatStoragePathOwned'), isTrue);
      expect(rules.contains('request.resource.data.encrypted == true'), isTrue);
    });

    test('support tickets are owner-read and create-only', () {
      expect(rules.contains('match /supportTickets/{ticketId}'), isTrue);
      expect(rules.contains('resource.data.userId == request.auth.uid'), isTrue);
      expect(rules.contains('request.resource.data.userId == request.auth.uid'), isTrue);
    });
  });

  group('server-only collections', () {
    test('message rate limits and purchases stay server controlled', () {
      expect(rules.contains('match /rateLimits/{docId}'), isTrue);
      expect(rules.contains('match /purchases/{purchaseId}'), isTrue);
      expect(rules.contains('allow create, update, delete: if false;'), isTrue);
    });
  });

  group('likes privacy', () {
    test('clients can only read their own outgoing likes', () {
      expect(rules.contains('match /likes/{likeId}'), isTrue);
      expect(
        rules.contains(
          'allow read: if isAuthenticated() && resource.data.fromUserId == request.auth.uid',
        ),
        isTrue,
      );
      expect(rules.contains('Incoming likes (toUserId == auth)'), isTrue);
    });

    test('subscription entitlement is owner-read and server-write only', () {
      expect(rules.contains('match /subscription/{docId}'), isTrue);
      expect(rules.contains('allow create, update, delete: if false;'), isTrue);
    });
  });

  group('match compatibility snapshot immutability', () {
    // B-09 replaced the match freeze-list with a client-write allowlist. These
    // fields are now server-owned because they are ABSENT from the allowlist,
    // not because each one is named in a denylist — which also covers fields
    // added to the schema later. The behavioural proof lives in
    // firebase/tests/firestore.security.emulator.test.mjs.
    String matchUpdateAllowlist() {
      final int start = rules.indexOf('function matchUpdateKeysAllowed()');
      expect(start, greaterThan(-1), reason: 'match update allowlist missing');
      return rules.substring(start, rules.indexOf('}', start));
    }

    test('clients cannot mutate compatibilitySnapshots or calculatedAt', () {
      final String allowlist = matchUpdateAllowlist();
      expect(allowlist.contains('compatibilitySnapshots'), isFalse);
      expect(allowlist.contains('compatibilityCalculatedAt'), isFalse);
      expect(rules.contains('matchUpdateKeysAllowed()'), isTrue);
    });

    test('clients cannot inject legacy compatibilityScore fields', () {
      final String allowlist = matchUpdateAllowlist();
      expect(allowlist.contains('compatibilityScore'), isFalse);
      expect(allowlist.contains('compatibilityBreakdown'), isFalse);
    });

    test('identity snapshot fields are not participant-writable', () {
      final String allowlist = matchUpdateAllowlist();
      for (final String field in <String>[
        'participantVerified',
        'participantNames',
        'participantPhotos',
        'userIds',
        'isActive',
        'matchBonusAwarded',
        'interactionBonusAwarded',
      ]) {
        expect(allowlist.contains(field), isFalse,
            reason: '$field must stay server-owned');
      }
    });

    test('per-participant maps are scoped to the calling user', () {
      expect(rules.contains('function matchMapOwnKeyOnly(key)'), isTrue);
      expect(rules.contains("matchMapOwnKeyOnly('isNewFor')"), isTrue);
      expect(rules.contains("matchMapOwnKeyOnly('unreadCounts')"), isTrue);
      expect(rules.contains('.hasOnly([request.auth.uid])'), isTrue);
    });

    test('match create remains server-only', () {
      expect(rules.contains('match /matches/{matchId}'), isTrue);
      expect(rules.contains('allow create, delete: if false'), isTrue);
    });
  });

  group('humor lab isolation', () {
    test('humor summary and interactions are owner-read CF-write only', () {
      expect(rules.contains('match /humor/{docId}'), isTrue);
      expect(rules.contains('match /humorInteractions/{contentId}'), isTrue);
      expect(
        rules.contains('Peers never read raw humor vectors'),
        isTrue,
      );
    });

    test('humorContent is readable only when approved and active', () {
      expect(rules.contains('match /humorContent/{contentId}'), isTrue);
      expect(
        rules.contains("resource.data.get('safetyStatus', '') == 'approved'"),
        isTrue,
      );
      expect(
        rules.contains("resource.data.get('active', false) == true"),
        isTrue,
      );
    });

    test('humor reports and moderation queue are not client-writable', () {
      expect(rules.contains('match /humorReports/{reportId}'), isTrue);
      expect(rules.contains('match /humorModerationQueue/{contentId}'), isTrue);
    });
  });
}
