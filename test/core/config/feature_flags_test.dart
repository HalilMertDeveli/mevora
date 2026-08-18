import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/feature_flags.dart';

void main() {
  test('feature flags default off until those products are ready', () {
    const flags = FeatureFlags();

    expect(flags.videoCallsEnabled, isFalse);
    expect(flags.spotifyLoginEnabled, isFalse);
    expect(flags.premiumEnabled, isFalse);
    expect(flags.aiRecommendationsEnabled, isFalse);
  });

  test('copyWith updates a single flag without scattering ifs', () {
    const flags = FeatureFlags();
    final enabled = flags.copyWith(videoCallsEnabled: true);

    expect(enabled.videoCallsEnabled, isTrue);
    expect(enabled.premiumEnabled, isFalse);
  });
}
