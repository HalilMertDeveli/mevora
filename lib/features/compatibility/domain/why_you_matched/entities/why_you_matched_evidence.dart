/// Machine-readable proof that a reason is based on real comparison data.
///
/// Generators must never emit a reason without evidence.
class WhyYouMatchedEvidence {
  const WhyYouMatchedEvidence({
    required this.type,
    this.values = const {},
  });

  /// Evidence kind, e.g. `commonInterests`, `sharedHumorAnswers`, `proximityKm`.
  final String type;

  /// Structured numeric/string values that support the claim.
  final Map<String, Object?> values;

  bool get isValid => type.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
        'type': type,
        'values': values,
      };

  factory WhyYouMatchedEvidence.fromJson(Map<String, dynamic> json) {
    final rawValues = json['values'];
    return WhyYouMatchedEvidence(
      type: '${json['type'] ?? ''}'.trim(),
      values: rawValues is Map
          ? Map<String, Object?>.from(rawValues)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is WhyYouMatchedEvidence &&
        other.type == type &&
        _mapEquals(other.values, values);
  }

  @override
  int get hashCode => Object.hash(type, values.length);

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
