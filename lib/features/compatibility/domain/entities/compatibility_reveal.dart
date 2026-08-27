/// A single verified Compatibility Reveal point (server or local engine).
enum CompatibilityRevealKind {
  personality,
  questions,
  music,
  relationship,
  preference,
  lifestyle,
}

class CompatibilityRevealPoint {
  const CompatibilityRevealPoint({
    required this.kind,
    required this.messageKey,
    this.messageArgs = const [],
    this.score,
  });

  final CompatibilityRevealKind kind;
  final String messageKey;
  final List<String> messageArgs;
  final int? score;

  factory CompatibilityRevealPoint.fromMap(Map<String, dynamic> raw) {
    return CompatibilityRevealPoint(
      kind: _kindFrom(raw['kind'] as String?),
      messageKey: (raw['messageKey'] as String?) ?? '',
      messageArgs: _stringList(raw['messageArgs']),
      score: raw['score'] is int ? raw['score'] as int : null,
    );
  }

  static CompatibilityRevealKind _kindFrom(String? value) {
    return switch (value) {
      'personality' => CompatibilityRevealKind.personality,
      'questions' => CompatibilityRevealKind.questions,
      'music' => CompatibilityRevealKind.music,
      'relationship' => CompatibilityRevealKind.relationship,
      'preference' => CompatibilityRevealKind.preference,
      'lifestyle' => CompatibilityRevealKind.lifestyle,
      _ => CompatibilityRevealKind.preference,
    };
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<String>().where((e) => e.isNotEmpty).toList();
  }
}

class CompatibilityRevealBreakdown {
  const CompatibilityRevealBreakdown({
    required this.relationshipScore,
    required this.interestScore,
    required this.lifestyleScore,
    this.questionScore,
    this.musicScore,
    this.communicationScore,
  });

  final int relationshipScore;
  final int interestScore;
  final int lifestyleScore;
  final int? questionScore;
  final int? musicScore;
  final int? communicationScore;

  factory CompatibilityRevealBreakdown.fromMap(Map<String, dynamic> raw) {
    int? optInt(Object? value) => value is int ? value : null;
    return CompatibilityRevealBreakdown(
      relationshipScore: raw['relationshipScore'] is int
          ? raw['relationshipScore'] as int
          : 0,
      interestScore: raw['interestScore'] is int
          ? raw['interestScore'] as int
          : 0,
      lifestyleScore: raw['lifestyleScore'] is int
          ? raw['lifestyleScore'] as int
          : 0,
      questionScore: optInt(raw['questionScore']),
      musicScore: optInt(raw['musicScore']),
      communicationScore: optInt(raw['communicationScore']),
    );
  }
}

/// Match Compatibility Reveal payload from `getMatchCompatibilityReveal`.
class CompatibilityReveal {
  const CompatibilityReveal({
    required this.available,
    required this.overallScore,
    this.isPremium = false,
    this.premiumRequired = false,
    this.points = const [],
    this.breakdown,
    this.reason,
  });

  static const unavailable = CompatibilityReveal(
    available: false,
    overallScore: 0,
  );

  final bool available;
  final int overallScore;
  final bool isPremium;
  final bool premiumRequired;
  final List<CompatibilityRevealPoint> points;
  final CompatibilityRevealBreakdown? breakdown;
  final String? reason;

  bool get showPremiumUpsell => available && premiumRequired && !isPremium;

  factory CompatibilityReveal.fromMap(Map<String, dynamic> raw) {
    final pointsRaw = raw['points'];
    final points = <CompatibilityRevealPoint>[];
    if (pointsRaw is List) {
      for (final item in pointsRaw) {
        if (item is Map) {
          points.add(
            CompatibilityRevealPoint.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    CompatibilityRevealBreakdown? breakdown;
    final breakdownRaw = raw['breakdown'];
    if (breakdownRaw is Map) {
      breakdown = CompatibilityRevealBreakdown.fromMap(
        Map<String, dynamic>.from(breakdownRaw),
      );
    }
    return CompatibilityReveal(
      available: raw['available'] == true,
      overallScore: raw['overallScore'] is int
          ? raw['overallScore'] as int
          : 0,
      isPremium: raw['isPremium'] == true,
      premiumRequired: raw['premiumRequired'] == true,
      points: points,
      breakdown: breakdown,
      reason: raw['reason'] as String?,
    );
  }
}
