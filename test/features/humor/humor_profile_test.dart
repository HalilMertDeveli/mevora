import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('building threshold and progress helpers', () {
    expect(HumorFeedPolicy.pageSize, 12);
    expect(HumorFeedPolicy.preloadAhead, 3);
    expect(HumorFeedPolicy.buildingThreshold, 15);
    expect(HumorFeedPolicy.isBuilding(14), isTrue);
    expect(HumorFeedPolicy.isBuilding(15), isFalse);

    const building = UserHumorProfile(
      interactionCount: 5,
      profileBuilding: true,
    );
    expect(HumorFeedPolicy.buildingProgress(building), closeTo(5 / 15, 0.001));
    expect(HumorProfileDisplay.remainingToReady(building), 10);
    expect(
      HumorProfileDisplay.buildingLabel(l10n, building),
      l10n.humorProfileBuilding,
    );
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
      'wordplay',
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
