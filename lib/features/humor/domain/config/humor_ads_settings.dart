/// Configurable Humor Lab ad policy (Remote Config / defaults).
/// Not a security boundary — premium entitlement is authoritative elsewhere.
class HumorAdsSettings {
  const HumorAdsSettings({
    this.enabled = true,
    this.contentInterval = 5,
    this.minInterval = 5,
    this.maxInterval = 20,
    this.minContentBeforeFirstAd = 5,
    this.minWatchSeconds = 5,
    this.cooldownSeconds = 30,
    this.provider = 'mevora_sponsored_break',
  });

  final bool enabled;

  /// Show an ad after this many humor contents (clamped to min/max).
  final int contentInterval;
  final int minInterval;
  final int maxInterval;

  /// Minimum unique content views before the first ad in a session.
  final int minContentBeforeFirstAd;

  /// Sponsored break must be visible at least this long before Continue.
  final int minWatchSeconds;
  final int cooldownSeconds;
  final String provider;

  int get effectiveInterval {
    final raw = contentInterval;
    if (raw < minInterval) return minInterval;
    if (raw > maxInterval) return maxInterval;
    return raw;
  }

  static const HumorAdsSettings defaults = HumorAdsSettings();

  @override
  bool operator ==(Object other) {
    return other is HumorAdsSettings &&
        other.enabled == enabled &&
        other.contentInterval == contentInterval &&
        other.minInterval == minInterval &&
        other.maxInterval == maxInterval &&
        other.minContentBeforeFirstAd == minContentBeforeFirstAd &&
        other.minWatchSeconds == minWatchSeconds &&
        other.cooldownSeconds == cooldownSeconds &&
        other.provider == provider;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        contentInterval,
        minInterval,
        maxInterval,
        minContentBeforeFirstAd,
        minWatchSeconds,
        cooldownSeconds,
        provider,
      );

  static HumorAdsSettings fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) {
      return defaults;
    }
    int asInt(Object? v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? fallback;
    }

    bool asBool(Object? v, bool fallback) {
      if (v is bool) return v;
      if (v is String) {
        if (v.toLowerCase() == 'true') return true;
        if (v.toLowerCase() == 'false') return false;
      }
      return fallback;
    }

    return HumorAdsSettings(
      enabled: asBool(json['enabled'], defaults.enabled),
      contentInterval: asInt(json['contentInterval'], defaults.contentInterval),
      minInterval: asInt(json['minInterval'], defaults.minInterval),
      maxInterval: asInt(json['maxInterval'], defaults.maxInterval),
      minContentBeforeFirstAd: asInt(
        json['minContentBeforeFirstAd'],
        defaults.minContentBeforeFirstAd,
      ),
      minWatchSeconds: asInt(json['minWatchSeconds'], defaults.minWatchSeconds),
      cooldownSeconds: asInt(json['cooldownSeconds'], defaults.cooldownSeconds),
      provider: (json['provider'] as String?)?.trim().isNotEmpty == true
          ? (json['provider'] as String).trim()
          : defaults.provider,
    );
  }

  /// Whether free user should see an ad after [contentViewedSinceLastAd] items.
  bool shouldShowAd({
    required bool isPremium,
    required int contentViewedSinceLastAd,
    required int sessionContentViews,
    required int adsShownInSession,
    DateTime? lastAdAt,
    DateTime? now,
  }) {
    if (isPremium || !enabled) {
      return false;
    }
    if (adsShownInSession == 0 &&
        sessionContentViews < minContentBeforeFirstAd) {
      return false;
    }
    if (contentViewedSinceLastAd < effectiveInterval) {
      return false;
    }
    final clock = now ?? DateTime.now();
    if (lastAdAt != null) {
      final elapsed = clock.difference(lastAdAt).inSeconds;
      if (elapsed < cooldownSeconds) {
        return false;
      }
    }
    return true;
  }
}
