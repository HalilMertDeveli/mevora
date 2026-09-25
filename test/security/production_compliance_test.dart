import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/chat/domain/chat_policy.dart';
import 'package:mevora/features/discovery/domain/services/discovery_candidate_filter.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/relationship/domain/services/relationship_match_rules.dart';
import 'package:mevora/features/safety/domain/models/report_reason.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

void main() {
  DateTime birthYearsAgo(int years) {
    final today = DateTime.now();
    return DateTime(today.year - years, today.month, today.day);
  }

  group('age compliance', () {
    test('17 is rejected and 18/19 are accepted at onboarding', () {
      expect(OnboardingValidators.validateAge(birthYearsAgo(17)).isError, isTrue);
      expect(OnboardingValidators.validateAge(birthYearsAgo(18)).isSuccess, isTrue);
      expect(OnboardingValidators.validateAge(birthYearsAgo(19)).isSuccess, isTrue);
    });

    test('exact 18th birthday is accepted', () {
      final today = DateTime.now();
      final eighteenthBirthday = DateTime(today.year - 18, today.month, today.day);
      expect(OnboardingValidators.validateAge(eighteenthBirthday).isSuccess, isTrue);
    });
  });

  group('matching exclusion', () {
    test('self, blocked, liked, and passed users are excluded locally', () {
      final filtered = DiscoveryCandidateFilter.apply<_Seed>(
        seeds: const [
          _Seed('self'),
          _Seed('blocked'),
          _Seed('liked'),
          _Seed('passed'),
          _Seed('near'),
        ],
        selfUid: 'self',
        blocked: {'blocked'},
        liked: {'liked'},
        passed: {'passed'},
        radiusKm: 100,
        uidOf: (seed) => seed.uid,
        distanceKmOf: (_) => 1,
      );
      expect(filtered.map((seed) => seed.uid), ['near']);
    });

    test('relationship suggestions reject self and blocked users', () {
      expect(
        RelationshipMatchRules.isEligible(
          selfUid: 'self',
          candidateUid: 'self',
          blocked: const {},
          passed: const {},
          alignedCount: 3,
        ),
        isFalse,
      );
      expect(
        RelationshipMatchRules.isEligible(
          selfUid: 'self',
          candidateUid: 'blocked-user',
          blocked: {'blocked-user'},
          passed: const {},
          alignedCount: 3,
        ),
        isFalse,
      );
    });

    test('users cannot swipe on themselves', () {
      expect(MatchEngine.isValidPair('a', 'a'), isFalse);
      expect(
        MatchEngine.canRecordSwipe(
          actorUid: 'a',
          targetUid: 'a',
          alreadySwiped: false,
          blocked: false,
        ),
        isFalse,
      );
    });

    test('self-likes never create a mutual match', () {
      final selfLike = MatchEngine.buildLike(
        fromUserId: 'a',
        toUserId: 'a',
        action: SwipeAction.like,
        createdAt: DateTime(2026),
      );
      expect(
        MatchEngine.shouldCreateMatch(
          forward: selfLike,
          reverse: selfLike,
          blocked: false,
          existingActiveMatch: false,
        ),
        isFalse,
      );
    });
  });

  group('messaging safety', () {
    test('blocked or inactive matches cannot send messages', () {
      final match = MatchEngine.buildMatch(
        uidA: 'a',
        uidB: 'b',
        createdAt: DateTime(2026),
      );
      expect(
        ChatPolicy.canSendMessage(
          match: match,
          senderId: 'a',
          receiverId: 'b',
          blocked: true,
        ),
        isFalse,
      );
      expect(
        ChatPolicy.canSendMessage(
          match: match.copyWith(isActive: false),
          senderId: 'a',
          receiverId: 'b',
          blocked: false,
        ),
        isFalse,
      );
    });
  });

  group('report and block policy', () {
    test('report reasons cover store-safe abuse categories', () {
      expect(ReportReason.values, contains(ReportReason.underage));
      expect(ReportReason.values, contains(ReportReason.fakeProfile));
      expect(ReportReason.fakeProfile.firestoreValue, 'fake_profile');
      expect(ReportReason.underage.firestoreValue, 'underage');
    });

    test('block ids are symmetric and block interaction', () {
      expect(
        SafetyPolicy.isBlocked(
          blockIds: {SafetyPolicy.blockId(blockerId: 'a', blockedUserId: 'b')},
          uidA: 'a',
          uidB: 'b',
        ),
        isTrue,
      );
      expect(
        SafetyPolicy.canInteract(matchActive: true, blocked: true),
        isFalse,
      );
    });
  });

  group('account deletion contract', () {
    test('delete flow uses server-side deleteUserAccount callable', () {
      final source = File(
        'lib/features/authentication/data/services/account_deletion_service.dart',
      ).readAsStringSync();
      expect(source.contains("'deleteUserAccount'"), isTrue);
      expect(source.contains('httpsCallable'), isTrue);
    });

    test('deleteAccount cloud function cleans auth, profile docs, and storage prefixes', () {
      final source = File('functions/src/deleteAccount.ts').readAsStringSync();
      expect(source.contains('deleteUserAccount'), isTrue);
      // The Auth record is removed through deleteAuthUserIfPresent, which
      // tolerates an already-deleted user so a retried deletion returns 200
      // instead of 500. Both the wiring and the underlying call are pinned;
      // the behaviour is covered by
      // functions/test/deleteAccountIdempotency.test.cjs.
      expect(source.contains('deleteAuthUserIfPresent(auth, uid)'), isTrue);
      expect(source.contains('client.deleteUser(uid)'), isTrue);
      expect(source.contains('deletePrefix'), isTrue);
      expect(source.contains(r'db.doc(`profiles/${uid}`)'), isTrue);
      expect(source.contains(r'deletePrefix(`profiles/${uid}/`)'), isTrue);
      expect(source.contains(r'users/${uid}/'), isTrue);
      expect(source.contains('passedUsers'), isTrue);
      expect(source.contains('callHistory'), isTrue);
      expect(source.contains('BATCH_LIMIT'), isTrue);
    });
  });
}

class _Seed {
  const _Seed(this.uid);
  final String uid;
}
