import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_category.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_evidence.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_result.dart';

/// Server payload from `getWhyYouMatched` (authoritative scores).
class WhyYouMatchedServerPayload {
  const WhyYouMatchedServerPayload({
    required this.available,
    required this.reasons,
    this.overallScore,
    this.peerUid,
    this.distanceKm,
    this.cacheHit = false,
    this.insufficientReason,
    this.generatedAtMs,
  });

  final bool available;
  final List<WhyYouMatchedReason> reasons;
  final int? overallScore;
  final String? peerUid;
  final double? distanceKm;
  final bool cacheHit;
  final String? insufficientReason;
  final int? generatedAtMs;

  WhyYouMatchedResult toResult() {
    if (!available || reasons.isEmpty) {
      return WhyYouMatchedResult(
        available: false,
        reasons: const [],
        overallScore: overallScore,
        insufficientReason: insufficientReason ?? 'not_enough_data',
      );
    }
    return WhyYouMatchedResult.fromReasons(
      reasons,
      overallScore: overallScore,
    );
  }

  /// Parses CF JSON. Ignores any client-injected fields outside the map.
  ///
  /// Anti-tamper: scores and evidence come only from this payload — callers
  /// must not merge local score overrides into [raw].
  static WhyYouMatchedServerPayload fromJson(
    Map<String, dynamic> raw, {
    // Kept so callers/tests can prove score overrides are discarded.
    Map<String, dynamic>? clientOverrides,
  }) {
    // Anti-tamper: never merge [clientOverrides] into scores or evidence.
    final _ = clientOverrides;

    final available = raw['available'] == true;
    final reasonsRaw = raw['reasons'];
    final reasons = <WhyYouMatchedReason>[];
    if (reasonsRaw is List) {
      for (final item in reasonsRaw) {
        if (item is! Map) continue;
        final mapped = _reasonFromJson(Map<String, dynamic>.from(item));
        if (mapped != null) reasons.add(mapped);
      }
    }

    return WhyYouMatchedServerPayload(
      available: available && reasons.isNotEmpty,
      reasons: List.unmodifiable(reasons),
      overallScore: _asInt(raw['overallScore']),
      peerUid: raw['peerUid']?.toString(),
      distanceKm: _asDouble(raw['distanceKm']),
      cacheHit: raw['cacheHit'] == true,
      insufficientReason: raw['reason']?.toString(),
      generatedAtMs: _asInt(raw['generatedAtMs']),
    );
  }

  static WhyYouMatchedReason? _reasonFromJson(Map<String, dynamic> json) {
    final evidenceRaw = json['evidence'];
    if (evidenceRaw is! Map) return null;
    final evidenceMap = Map<String, dynamic>.from(evidenceRaw);
    final type = '${evidenceMap['type'] ?? ''}'.trim();
    if (type.isEmpty) return null;

    final valuesRaw = evidenceMap['values'];
    final values = <String, Object?>{};
    if (valuesRaw is Map) {
      for (final entry in valuesRaw.entries) {
        final key = entry.key.toString().toLowerCase();
        // Never accept coordinate / secret keys from wire.
        if (_forbiddenEvidenceKeys.contains(key)) continue;
        values[entry.key.toString()] = entry.value;
      }
    }

    final category = WhyYouMatchedCategoryX.tryParse(
          '${json['category'] ?? ''}',
        ) ??
        WhyYouMatchedCategory.interests;

    final argsRaw = json['descriptionArgs'] ?? json['description_args'];
    final args = <String>[];
    if (argsRaw is List) {
      for (final a in argsRaw) {
        args.add(a.toString());
      }
    }

    final strengthName = '${json['strength'] ?? ''}';
    WhyYouMatchedStrength? strength;
    for (final value in WhyYouMatchedStrength.values) {
      if (value.name == strengthName) {
        strength = value;
        break;
      }
    }

    final created = WhyYouMatchedReason.create(
      id: '${json['id'] ?? ''}',
      category: category,
      score: _asInt(json['score']) ?? 0,
      strength: strength,
      title: '${json['titleKey'] ?? json['title'] ?? ''}',
      description: '${json['descriptionKey'] ?? json['description'] ?? ''}',
      descriptionArgs: args,
      evidence: WhyYouMatchedEvidence(type: type, values: values),
      confidence: (_asDouble(json['confidence']) ?? 0.5).clamp(0.0, 1.0),
      priority: _asInt(json['priority']),
    );
    return created.reason;
  }

  static const _forbiddenEvidenceKeys = {
    'lat',
    'lng',
    'latitude',
    'longitude',
    'geohash',
    'coordinates',
    'accesstoken',
    'refreshtoken',
  };

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value');
  }

  static double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}
