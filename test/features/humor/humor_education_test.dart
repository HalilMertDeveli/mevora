import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/services/humor_education_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HumorEducationPolicy', () {
    test('rating help hides after threshold or dismiss', () {
      expect(
        HumorEducationPolicy.shouldShowRatingHelp(
          interactionCount: 2,
          dismissed: false,
        ),
        isTrue,
      );
      expect(
        HumorEducationPolicy.shouldShowRatingHelp(
          interactionCount: 5,
          dismissed: false,
        ),
        isFalse,
      );
      expect(
        HumorEducationPolicy.shouldShowRatingHelp(
          interactionCount: 1,
          dismissed: true,
        ),
        isFalse,
      );
    });

    test('milestones are sparse exact counts', () {
      expect(HumorEducationPolicy.isHintMilestone(1), isTrue);
      expect(HumorEducationPolicy.isHintMilestone(2), isFalse);
      expect(HumorEducationPolicy.isShapingMilestone(12), isTrue);
      expect(HumorEducationPolicy.isProfileMilestone(20), isTrue);
      expect(HumorEducationPolicy.isProfileMilestone(19), isFalse);
    });

    test('learning progress clamps', () {
      expect(HumorEducationPolicy.learningProgress(0), 0);
      expect(HumorEducationPolicy.learningProgress(15), 1);
      expect(HumorEducationPolicy.learningProgress(7), closeTo(7 / 15, 0.001));
    });
  });

  group('HumorEducationStore', () {
    test('intro seen is per uid', () async {
      SharedPreferences.setMockInitialValues({});
      final store = HumorEducationStore(
        preferences: await SharedPreferences.getInstance(),
      );
      const a = 'user_a';
      const b = 'user_b';

      expect(await store.isIntroSeen(a), isFalse);
      await store.markIntroSeen(a);
      expect(await store.isIntroSeen(a), isTrue);
      expect(await store.isIntroSeen(b), isFalse);

      await store.markAdInfoSeen(a);
      expect(await store.isAdInfoSeen(a), isTrue);
      expect(await store.isAdInfoSeen(b), isFalse);

      expect(await store.wasMilestoneShown(a, 12), isFalse);
      await store.markMilestoneShown(a, 12);
      expect(await store.wasMilestoneShown(a, 12), isTrue);
    });
  });
}
