class SmartBoostPreview {
  const SmartBoostPreview({
    required this.suitableActiveCount,
    required this.activeUserCount,
    required this.newUsersLast30m,
    required this.profileQualityScore,
    required this.suggestions,
    required this.lowTraffic,
    required this.hasActiveBoost,
    required this.durationMinutes,
    required this.multiplier,
    this.productId = 'mevora_smart_boost_30m',
  });

  final int suitableActiveCount;
  final int activeUserCount;
  final int newUsersLast30m;
  final int profileQualityScore;
  final List<String> suggestions;
  final bool lowTraffic;
  final bool hasActiveBoost;
  final int durationMinutes;
  final double multiplier;
  final String productId;

  static SmartBoostPreview? fromMap(Map<String, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final quality = raw['profileQuality'];
    final suggestions = <String>[];
    var score = 0;
    if (quality is Map) {
      score = (quality['score'] as num?)?.round() ?? 0;
      final list = quality['suggestions'];
      if (list is List) {
        for (final item in list) {
          suggestions.add(item.toString());
        }
      }
    }
    return SmartBoostPreview(
      suitableActiveCount:
          (raw['suitableActiveCount'] as num?)?.round() ?? 0,
      activeUserCount: (raw['activeUserCount'] as num?)?.round() ?? 0,
      newUsersLast30m: (raw['newUsersLast30m'] as num?)?.round() ?? 0,
      profileQualityScore: score,
      suggestions: suggestions,
      lowTraffic: raw['lowTraffic'] == true,
      hasActiveBoost: raw['hasActiveBoost'] == true,
      durationMinutes: (raw['durationMinutes'] as num?)?.round() ?? 30,
      multiplier: (raw['multiplier'] as num?)?.toDouble() ?? 1.25,
      productId: raw['productId']?.toString() ?? 'mevora_smart_boost_30m',
    );
  }
}
