import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/config/remote_config/mevora_remote_config.dart';
import 'package:mevora/core/paging/page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  test('remote config maps onto feature flags without becoming security', () {
    const flags = FeatureFlags();
    const remote = MevoraRemoteConfig(
      minimumAge: 21,
      maxDiscoveryDistance: 40,
      maxDailyLikes: 12,
      videoCallEnabled: true,
      maintenanceMode: true,
    );
    final merged = remote.toFeatureFlags(flags);
    expect(merged.minimumAge, 21);
    expect(merged.maxDiscoveryDistanceKm, 40);
    expect(merged.maxDailyLikes, 12);
    expect(merged.videoCallsEnabled, isTrue);
    expect(merged.maintenanceMode, isTrue);
    expect(RemoteConfigKeys.minimumAge, 'minimumAge');
  });

  test('discovery pages are cursor based', () {
    const page = Page<DiscoveryCard>(
      items: [],
      nextCursor: 'abc',
    );
    expect(page.hasMore, isTrue);
    expect(const Page<DiscoveryCard>(items: []).hasMore, isFalse);
  });
}
