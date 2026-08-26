import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_access.dart';

void main() {
  group('ProfileQuestionAnswerAccess', () {
    test('owner can always view', () {
      expect(
        ProfileQuestionAnswerAccess.canView(
          viewerUid: 'a',
          profileUid: 'a',
        ),
        isTrue,
      );
    });

    test('active match unlocks answers for both participants', () {
      final match = Match(
        id: 'a_b',
        userIds: ['a', 'b'],
        createdAt: DateTime.utc(2026, 8, 24),
        isActive: true,
      );
      expect(
        ProfileQuestionAnswerAccess.canView(
          viewerUid: 'a',
          profileUid: 'b',
          match: match,
        ),
        isTrue,
      );
      expect(
        ProfileQuestionAnswerAccess.canView(
          viewerUid: 'b',
          profileUid: 'a',
          match: match,
        ),
        isTrue,
      );
    });

    test('unmatched or inactive match keeps answers locked', () {
      final inactive = Match(
        id: 'a_b',
        userIds: ['a', 'b'],
        createdAt: DateTime.utc(2026, 8, 24),
        isActive: false,
      );
      expect(
        ProfileQuestionAnswerAccess.canView(
          viewerUid: 'a',
          profileUid: 'b',
          match: inactive,
        ),
        isFalse,
      );
      expect(
        ProfileQuestionAnswerAccess.canView(
          viewerUid: 'a',
          profileUid: 'c',
          match: inactive,
        ),
        isFalse,
      );
      expect(
        ProfileQuestionAnswerAccess.canView(
          viewerUid: 'a',
          profileUid: 'b',
        ),
        isFalse,
      );
    });

    test('match id is canonical regardless of uid order', () {
      expect(
        ProfileQuestionAnswerAccess.matchIdFor('z', 'a'),
        ProfileQuestionAnswerAccess.matchIdFor('a', 'z'),
      );
    });
  });
}
