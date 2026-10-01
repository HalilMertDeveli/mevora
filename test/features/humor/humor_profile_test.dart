import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('building progress follows the server calibration, not a count kept '
      'on the client', () {
    expect(HumorFeedPolicy.pageSize, 12);
    expect(HumorFeedPolicy.preloadAhead, 3);

    const building = UserHumorProfile(
      interactionCount: 5,
      profileBuilding: true,
      calibration: HumorCalibration(completedCount: 5, totalCount: 15),
    );
    expect(HumorFeedPolicy.buildingProgress(building), closeTo(5 / 15, 0.001));
    expect(
      HumorProfileDisplay.buildingLabel(l10n, building),
      l10n.humorProfileBuilding,
    );

    // A calibration one item shorter is simply a different total.
    const shorter = UserHumorProfile(
      profileBuilding: true,
      calibration: HumorCalibration(completedCount: 7, totalCount: 14),
    );
    expect(HumorFeedPolicy.buildingProgress(shorter), closeTo(0.5, 0.001));

    // However many ratings there are: without the server's total, no
    // progress is claimed.
    const unknown = UserHumorProfile(
      interactionCount: 40,
      profileBuilding: true,
    );
    expect(HumorFeedPolicy.buildingProgress(unknown), 0);

    const ready = UserHumorProfile(profileBuilding: false);
    expect(HumorFeedPolicy.buildingProgress(ready), 1);
  });

  test('visibleTopVibes prefers explicit topVibes then vector', () {
    const withTop = UserHumorProfile(
      topVibes: [
        HumorVibe(category: HumorCategory.sarcasm, value: 88),
        HumorVibe(category: HumorCategory.absurd, value: 70),
      ],
    );
    expect(
      HumorProfileDisplay.visibleTopVibes(withTop).first.category,
      HumorCategory.sarcasm,
    );

    const fromVector = UserHumorProfile(
      profileBuilding: false,
      vector: {
        HumorCategory.meme: 91,
        HumorCategory.dry: 40,
        HumorCategory.silly: 60,
      },
    );
    final vibes = HumorProfileDisplay.visibleTopVibes(fromVector);
    expect(vibes.first.category, HumorCategory.meme);
    expect(
      HumorProfileDisplay.buildingLabel(l10n, fromVector),
      l10n.humorProfileTitle,
    );
    expect(
      HumorProfileDisplay.categoryLabel(l10n, HumorCategory.wordplay),
      l10n.humorCategoryWordplay,
    );
  });

  test('shouldPrefetch near end of page', () {
    expect(
      HumorFeedPolicy.shouldPrefetch(
        currentIndex: 9,
        itemCount: 12,
        hasMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
    expect(
      HumorFeedPolicy.shouldPrefetch(
        currentIndex: 2,
        itemCount: 12,
        hasMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
  });
}
